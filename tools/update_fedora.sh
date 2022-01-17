#!/bin/bash -x

regex="kernel-debuginfo-[4-9]+\.[0-9]+\.[0-9]+\-.*x86_64.rpm"

# Iterating on the supported fedora versions 29 to 34.
for fedoraver in fedora29 fedora30 fedora31 fedora32 fedora33 fedora34; do
    fedora_version=${fedoraver/fedora/}

    # Creating a regex for the kernels depending on the ubuntu version.
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

    # Extracting from the remote bucket the kernel versions we already handled (either successfully or failed).
    # Thus we will look for kernel we didn't handle it, so we will reduce run time of the script.
    # The line gets a list of all kernels in the remote bucket and extracts the kernel version from their name.
    gs_names=$(gsutil ls gs://btfhub/fedora/${fedora_version}/x86_64/ | sed "s,gs://btfhub/fedora/${fedora_version}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

    # Downloading the package list from the two repositories. Those packages contains the kernel debug symbols with their remote location.
    echo "INFO: downloading ${repository01} information"
    lynx -dump -listonly ${repository01} | tail -n+4 > ${fedoraver}
    echo "INFO: downloading ${repository02} information"
    lynx -dump -listonly ${repository02} | tail -n+4 >> ${fedoraver}

    [[ ! -f ${fedoraver} ]] && exiterr "no ${fedoraver} packages file found"

    # Taking from the packages only packages that matches the regex.
    grep -E "${regex}" ${fedoraver} | awk '{print $2}' > packages
    rm ${fedoraver}

    # Iterating over packages
    sort packages | while read -r line; do

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
      	axel -4 -n 16 "${url}" -o ${version}.rpm
        if [ ! -f "${version}.rpm" ]; then
            echo "WARN: ${version}.rpm could not be downloaded"
            continue
        fi

        # Extracting vmlinux file from rpm package
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

        # Extracting the full BTF from the vmlinux file.
        echo "INFO: generating BTF file: ${version}.btf"
        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
        # Compressing the BTF.
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
        # Uploading it to the bucket.
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
