#!/bin/bash -x

# Extracting from the remote bucket the kernel versions we already handled (either successfully or failed).
# Thus we will look for kernel we didn't handle it, so we will reduce run time of the script.
# The line gets a list of all kernels in the remote bucket and extracts the kernel version from their name.
gs_names=$(gsutil ls gs://btfhub/amzn/2/x86_64/ | sed 's,gs://btfhub/amzn/2/x86_64/,,g' | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

repository=https://amazonlinux-2-repos-us-east-2.s3.dualstack.us-east-2.amazonaws.com/2/core/latest/debuginfo/x86_64/mirror.list

# Downloading from a fixed location the URL for the remote repository holding the packages.
echo "INFO: downloading ${repository} mirror list"
wget $repository
echo "INFO: downloading ${repository} information"
# Downloading from the remote repository a compress sqlite3 file that contains a table with all kernel packages and their remote location.
wget "$(head -1 mirror.list)/repodata/primary.sqlite.gz"
rm -f mirror.list

# Extracting the compressed sqlite file.
gzip -d primary.sqlite.gz
rm -f primary.sqlite.gz

# primary.sqlite contains a table with all packages can be downloaded. We look for packages with name that contains `kernel-debuginfo` but does not contain `common`.
# We strip `..` from their location.
packages=$(sqlite3 primary.sqlite "select location_href FROM packages WHERE name like 'kernel-debuginfo%' and name not like '%common%'" | sed 's#\.\./##g')
rm -f primary.sqlite

# Iterating over the packages.
for line in $packages; do
    # Crafting the URL for downloading the debug symbols and the kernel version we are handling with.
    url=${line}
    filename=$(basename "${line}")
    # shellcheck disable=SC2001
    version=$(echo "${filename}" | sed 's:kernel-debuginfo-\(.*\).rpm:\1:g')

    # Checking that we didn't handle that kernel version yet.
    # If we did, we continue to the next kernel.
    if [[ "${gs_names[*]}" =~ ${version} ]]; then
        echo "INFO: file ${version}.btf already exists"
        continue
    fi

    echo URL: "${url}"
    echo FILENAME: "${filename}"
    echo VERSION: "${version}"

    # Parallel downloading of the kernel.
    axel -4 -n 16 "http://amazonlinux.us-east-1.amazonaws.com/${url}" -o ${version}.rpm
    if [ ! -f "${version}.rpm" ]; then
        echo "WARN: ${version}.rpm could not be downloaded"
        continue
    fi

    # Extracting vmlinux file from rpm package.
    vmlinux=.$(rpmquery -qlp "${version}.rpm" 2>&1 | grep vmlinux)
    echo "INFO: extracting vmlinux from: ${version}.rpm"
    rpm2cpio "${version}.rpm" | cpio --to-stdout -i "${vmlinux}" > "./${version}.vmlinux" || \
    {
        echo "WARN: could not deal with ${version}, cleaning and moving on..."
        rm -rf "./usr"
        rm -rf "${version}.rpm"
        rm -rf "${version}.vmlinux"
        gsutil cp "${version}.failed" gs://btfhub/amzn/2/x86_64/"${version}.failed"
        continue
    }

    # Extracting the full BTF from the vmlinux file.
    echo "INFO: generating BTF file: ${version}.btf"
    pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
    # Compressing the BTF.
    tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
    # Uploading it to the bucket.
    gsutil cp ./${version}.btf.tar.xz gs://btfhub/amzn/2/x86_64/${version}.btf.tar.xz

    rm "${version}.rpm"
    rm "${version}.btf"
    rm "${version}.btf.tar.xz"
    rm "${version}.vmlinux"

done

rm -f packages

exit 0
