#!/bin/bash -x

gs_names=$(gsutil ls gs://btfhub/amzn/2/x86_64/ | sed 's,gs://btfhub/amzn/2/x86_64/,,g' | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

repository=https://amazonlinux-2-repos-us-east-2.s3.dualstack.us-east-2.amazonaws.com/2/core/latest/debuginfo/x86_64/mirror.list

echo "INFO: downloading ${repository} mirror list"
wget $repository
echo "INFO: downloading ${repository} information"
wget "$(head -1 mirror.list)/repodata/primary.sqlite.gz"
rm -f mirror.list

gzip -d primary.sqlite.gz
rm -f primary.sqlite.gz

packages=$(sqlite3 primary.sqlite "select location_href FROM packages WHERE name like 'kernel-debuginfo%' and name not like '%common%'" | sed 's#\.\./##g')
rm -f primary.sqlite

for line in $packages; do
    url=${line}
    filename=$(basename "${line}")
    # shellcheck disable=SC2001
    version=$(echo "${filename}" | sed 's:kernel-debuginfo-\(.*\).rpm:\1:g')

    if [[ "${gs_names[*]}" =~ ${version} ]]; then
        echo "INFO: file ${version}.btf already exists"
        continue
    fi

    echo URL: "${url}"
    echo FILENAME: "${filename}"
    echo VERSION: "${version}"

    axel -4 -n 16 "http://amazonlinux.us-east-1.amazonaws.com/${url}" -o ${version}.rpm
    if [ ! -f "${version}.rpm" ]; then
        echo "WANR: ${version}.rpm could not be downloaded"
        continue
    fi

    vmlinux=.$(rpmquery -qlp "${version}.rpm" 2>&1 | grep vmlinux)
    echo "INFO: extracting vmlinux from: ${version}.rpm"
    rpm2cpio "${version}.rpm" | cpio --to-stdout -i "${vmlinux}" > "./${version}.vmlinux" || \
    {
        echo "WANR: could not deal with ${version}, cleaning and moving on..."
        rm -rf "./usr"
        rm -rf "${version}.rpm"
        rm -rf "${version}.vmlinux"
        gsutil cp "${version}.failed" gs://btfhub/amzn/2/x86_64/"${version}.failed"
        continue
    }

    # generate BTF raw file from DWARF data
    echo "INFO: generating BTF file: ${version}.btf"
    pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
    tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
    gsutil cp ./${version}.btf.tar.xz gs://btfhub/amzn/2/x86_64/${version}.btf.tar.xz

    rm "${version}.rpm"
    rm "${version}.btf"
    rm "${version}.btf.tar.xz"
    rm "${version}.vmlinux"

done

rm -f packages

exit 0
