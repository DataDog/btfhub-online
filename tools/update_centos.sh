#!/bin/bash

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

    # Downloading repository packages
    lynx -dump -listonly ${repository} | tail -n+4 > "${centosver}"
    [[ ! -f ${centosver} ]] && exiterr "no ${centosver} packages file found"
    # Extracting the pacakges that fit the regex
    packages=$(grep -E "${regex}" "${centosver}" | awk '{print $2}')
    rm "${centosver}"

    echo $packages | rev | cut -d/ -f1 | rev | sed 's/kernel-debuginfo-//g' | sed 's/.rpm//g' | sort > packages_names
    # Getting all kernel versions that we already produced them a BTF file
    gsutil ls gs://btfhub/centos/${centos_num}/x86_64/ | sed "s,gs://btfhub/centos/${centos_num}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort > gs_names
    # Getting the new kernels that does not have a BTF file
    new_packages=$(comm -23 packages_names gs_names)
    rm -f gs_names packages_names

    for package in $new_packages; do
        url=${package}
        filename=$(basename "${package}")
        # shellcheck disable=SC2001
        version=$(echo "${filename}" | sed 's:kernel-debuginfo-\(.*\).rpm:\1:g')

        echo URL: "${url}"
        echo FILENAME: "${filename}"
        echo VERSION: "${version}"

        axel -4 -n 8 "${url}"
        mv "${filename}" "${version}.rpm"
        if [ ! -f "${version}.rpm" ]; then
          echo "WARN: ${version}.rpm could not be downloaded"
          continue
        fi

        vmlinux=.$(rpmquery -qlp "${version}.rpm" 2>&1 | grep vmlinux)
        echo "INFO: extracting vmlinux from: ${version}.rpm"
        rpm2cpio "${version}.rpm" | cpio --to-stdout -i "${vmlinux}" > "./${version}.vmlinux" || \
        {
            echo "WARN: could not deal with ${version}, cleaning and moving on..."
            rm -rf "${version}.rpm"
            rm -rf "${version}.vmlinux"
            touch "${version}.failed"
            gsutil cp "${version}.failed" gs://btfhub/centos/${centos_num}/x86_64/"${version}.failed"
            continue
        }

        # generate BTF raw file from DWARF data
        echo "INFO: generating BTF file: ${version}.btf"
        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"

        rm "${version}.rpm"
        rm "${version}.btf"
        rm "${version}.vmlinux"
        gsutil cp ./${version}.btf.tar.xz gs://btfhub/centos/${centos_num}/x86_64/${version}.btf.tar.xz
        rm ${version}.btf.tar.xz
    done

  rm -f packages
done

exit 0
