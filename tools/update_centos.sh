#!/bin/bash -x

regex="kernel-debuginfo-[4-9]+\.[0-9]+\.[0-9]+\-.*x86_64.rpm"

for centosver in centos7 centos8; do
    centos_num=${centosver/centos/}
    # Decide on the ftp url based on the centos version
    case "${centosver}" in
    "centos7")
      repository="http://mirror.facebook.net/centos-debuginfo/7/x86_64/"
      ;;
    "centos8")
      repository="http://mirror.facebook.net/centos-debuginfo/8/x86_64/Packages/"
      ;;
    esac

    gs_names=$(gsutil ls gs://btfhub/centos/${centos_num}/x86_64/ | sed "s,gs://btfhub/centos/${centos_num}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

    echo "INFO: downloading ${repository} information"
    lynx -dump -listonly ${repository} | tail -n+4 > "${centosver}"
    [[ ! -f ${centosver} ]] && exiterr "no ${centosver} packages file found"
    grep -E "${regex}" "${centosver}" | awk '{print $2}' > packages
    rm "${centosver}"

    sort packages | while read -r line; do

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

        axel -4 -n 16 "${url}" -o ${version}.rpm
        if [ ! -f "${version}.rpm" ]; then
            echo "WARN: ${version}.rpm could not be downloaded"
            continue
        fi

        vmlinux=.$(rpmquery -qlp "${version}.rpm" 2>&1 | grep vmlinux)
        echo "INFO: extracting vmlinux from: ${version}.rpm"
        rpm2cpio "${version}.rpm" | cpio --to-stdout -i "${vmlinux}" > "./${version}.vmlinux" || \
        {
            echo "WARN: could not deal with ${version}, cleaning and moving on..."
            rm -rf "./usr"
            rm -rf "${version}.rpm"
            rm -rf "${version}.vmlinux"
            gsutil cp "${version}.failed" gs://btfhub/centos/${centos_num}/x86_64/"${version}.failed"
            continue
        }

        # generate BTF raw file from DWARF data
        echo "INFO: generating BTF file: ${version}.btf"
        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
        gsutil cp ./${version}.btf.tar.xz gs://btfhub/centos/${centos_num}/x86_64/${version}.btf.tar.xz

        rm "${version}.rpm"
        rm "${version}.btf"
        rm "${version}.btf.tar.xz"
        rm "${version}.vmlinux"

      done

    rm -f packages
done

echo "Done"

exit 0
