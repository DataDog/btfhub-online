#!/bin/bash -x

regex="kernel-debuginfo-[4-9]+\.[0-9]+\.[0-9]+\-.*x86_64.rpm"

# Iterating on the supported centos versions 7 and 8.
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

    # Extracting from the remote bucket the kernel versions we already handled (either successfully or failed).
    # Thus we will look for kernel we didn't handle it, so we will reduce run time of the script.
    # The line gets a list of all kernels in the remote bucket and extracts the kernel version from their name.
    gs_names=$(gsutil ls gs://btfhub/centos/${centos_num}/x86_64/ | sed "s,gs://btfhub/centos/${centos_num}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

    echo "INFO: downloading ${repository} information"
    # Downloading the package list from the two repositories. Those packages contains the kernel debug symbols with their remote location.
    lynx -dump -listonly ${repository} | tail -n+4 > "${centosver}"
    [[ ! -f ${centosver} ]] && exiterr "no ${centosver} packages file found"

    # Taking from the packages only packages that matches the regex.
    grep -E "${regex}" "${centosver}" | awk '{print $2}' > packages
    rm "${centosver}"

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
            gsutil cp "${version}.failed" gs://btfhub/centos/${centos_num}/x86_64/"${version}.failed"
            continue
        }

        # Extracting the full BTF from the vmlinux file.
        echo "INFO: generating BTF file: ${version}.btf"
        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
        # Compressing the BTF.
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
        # Uploading it to the bucket.
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
