#!/bin/bash -x

regex="kernel-debuginfo-[4-9]+\.[0-9]+\.[0-9]+\-.*x86_64.rpm"

for fedoraver in fedora29 fedora30 fedora31 fedora32 fedora33 fedora34; do
    fedora_version=${fedoraver/fedora/}

    case "${fedoraver}" in
    "fedora29" | "fedora30" | "fedora31")
      repository01=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/"${fedora_version}/Everything/x86_64/debug/tree/Packages/k/"
      repository02=https://archives.fedoraproject.org/pub/archive/fedora/linux/updates/"${fedora_version}/Everything/x86_64/debug/Packages/k/"
      ;;
    "fedora32" | "fedora33" | "fedora34")
      repository01=https://dl.fedoraproject.org/pub/fedora/linux/releases/"${fedora_version}/Everything/x86_64/debug/tree/Packages/k/"
      repository02=https://dl.fedoraproject.org/pub/fedora/linux/releases/"${fedora_version}/Everything/x86_64/debug/tree/Packages/k/"
      ;;
    esac

    gs_names=$(gsutil ls gs://btfhub/fedora/${fedora_version}/x86_64/ | sed "s,gs://btfhub/fedora/${fedora_version}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

    echo "INFO: downloading ${repository01} information"
    lynx -dump -listonly ${repository01} | tail -n+4 > ${fedoraver}
    echo "INFO: downloading ${repository02} information"
    lynx -dump -listonly ${repository02} | tail -n+4 >> ${fedoraver}

    [[ ! -f ${fedoraver} ]] && exiterr "no ${fedoraver} packages file found"

    grep -E "${regex}" ${fedoraver} | awk '{print $2}' > temp
    mv temp packages ; rm ${fedoraver}

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
            gsutil cp "${version}.failed" gs://btfhub/fedora/${fedora_version}/x86_64/"${version}.failed"
  	        continue
        }

        # generate BTF raw file from DWARF data
        echo "INFO: generating BTF file: ${version}.btf"
        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
        gsutil cp "${version}.btf.tar.xz" gs://btfhub/fedora/${fedora_version}/x86_64/"${version}.btf.tar.xz"

        rm "${version}.rpm"
        rm "${version}.btf"
        rm "${version}.btf.tar.xz"
        rm "${version}.vmlinux"

    done

    rm -f packages
done

echo "Done"

exit 0
