#!/bin/bash -x

repository="http://ddebs.ubuntu.com"

# Iterating on the supported ubuntu versions bionic (18.04) and focal (20.04).
for ubuntuver in trusty xenial bionic focal; do
    # Creating a regex for the kernels depending on the ubuntu version.
    case "${ubuntuver}" in
    "trusty")
        regex="(linux-image-unsigned-(4.15.0|4.4.0)-.*-(generic|azure)-dbgsym)"
        ubuntu_number=14.04
        ;;
    "xenial")
        regex="(linux-image-unsigned-(4.15.0|4.4.0)-.*-(generic|azure|gcp)-dbgsym|linux-image-4.15.0-.*-aws-dbgsym)"
        ubuntu_number=16.04
        ;;
    "bionic")
        regex="(linux-image-unsigned-(4.15.0|5.4.0)-.*-(generic|azure|gcp|gke)-dbgsym|linux-image-(4.15.0|5.4.0)-.*-aws-dbgsym)"
        ubuntu_number=18.04
        ;;
    "focal")
        regex="(linux-image-unsigned-(5.4.0|5.8.0|5.11.0)-.*-(generic|azure|gcp|gke)-dbgsym|linux-image-(5.4.0|5.8.0|5.11.0)-.*-aws-dbgsym)"
        ubuntu_number=20.04
        ;;
    *)
    continue
        ;;
    esac

    # Extracting from the remote bucket the kernel versions we already handled (either successfully or failed).
    # Thus we will look for kernel we didn't handle it, so we will reduce run time of the script.
    # The line gets a list of all kernels in the remote bucket and extracts the kernel version from their name.
    gs_names=$(gsutil ls gs://btfhub/ubuntu/${ubuntu_number}/x86_64/ | sed "s,gs://btfhub/ubuntu/${ubuntu_number}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

    # Downloading the package list and the package updates list. Those packages contains the kernel debug symbols with their remote location.
    wget http://ddebs.ubuntu.com/dists/${ubuntuver}/main/binary-amd64/Packages -O ${ubuntuver}
    wget http://ddebs.ubuntu.com/dists/${ubuntuver}-updates/main/binary-amd64/Packages -O ${ubuntuver}-updates

    # Checking that we have downloaded both files.
    [ ! -f ${ubuntuver} ] && exiterr "no ${ubuntuver} packages file found"
    [ ! -f ${ubuntuver}-updates ] && exiterr "no ${ubuntuver}-updates packages file found"

    # Taking from the packages only packages that matches the regex.
    grep -E '^(Package|Filename):' ${ubuntuver} | grep --no-group-separator -A1 -E "^Package: ${regex}" > packages
    grep -E '^(Package|Filename):' ${ubuntuver}-updates | grep --no-group-separator -A1 -E "Package: ${regex}" >> packages

    # Deleting the packages files.
    rm ${ubuntuver}
    rm ${ubuntuver}-updates

    # Iterating over packages names. We look for all lines starting with `Package: ` in the packages file.
    # Then we strip the beginning of `Package: ` from the line to obtain the package name only.
    # Then we sort the packages and iterating over them.
    grep "Package:" packages | sed 's:Package\: ::g' | sort | while read -r package; do

        # Crafting the URL for downloading the debug symbols and the kernel version we are handling with.
        filepath=$(grep -A1 "${package}" packages | grep -v "^Package: " | sed 's:Filename\: ::g')
        url="${repository}/${filepath}"
        filename=$(basename "${filepath}")
        version=$(echo "${filename}" | sed 's:linux-image-::g' | sed 's:-dbgsym.*::g' | sed 's:unsigned-::g')

        # Checking that we didn't handle that kernel version yet.
        # If we did, we continue to the next kernel.
        if [[ "${gs_names[*]}" =~ ${version} ]]; then
            echo "INFO: file ${version}.btf already exists"
            continue
        fi

        echo URL: "${url}"
        echo FILEPATH: "${filepath}"
        echo FILENAME: "${filename}"
        echo VERSION: "${version}"

        # Parallel downloading of the kernel.
        axel -4 -n 16 "${url}" -o ${version}.ddeb
        if [ ! -f "${version}.ddeb" ]
        then
          echo "WARN: ${version}.ddeb could not be downloaded"
          continue
        fi

        # Extracting vmlinux file from ddeb package
        dpkg --fsys-tarfile "${version}.ddeb" | tar xvf - "./usr/lib/debug/boot/vmlinux-${version}" || \
        {
            echo "WARN: could not deal with ${version}, cleaning and moving on..."
            rm -rf "./usr"
            rm -rf "${version}.ddeb"
            gsutil cp ./${version}.failed gs://btfhub/ubuntu/${ubuntu_number}/x86_64/${version}.failed
            continue
        }

        mv "./usr/lib/debug/boot/vmlinux-${version}" "./${version}.vmlinux" || \
        {
            echo "WARN: could not rename vmlinux ${version}, cleaning and moving on..."
            rm -rf "./usr"
            rm -rf "${version}.ddeb"
            gsutil cp ./${version}.failed gs://btfhub/ubuntu/${ubuntu_number}/x86_64/${version}.failed
            continue
        }

        rm -rf "./usr"

        # Extracting the full BTF from the vmlinux file.
        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"

        # Compressing the BTF.
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"

        # Uploading it to the bucket.
        gsutil cp ./${version}.btf.tar.xz gs://btfhub/ubuntu/${ubuntu_number}/x86_64/${version}.btf.tar.xz

        rm "${version}.ddeb"
        rm "${version}.btf"
        rm "${version}.btf.tar.xz"
        rm "${version}.vmlinux"

    done

    pwd
    rm -f packages
done

echo "Done"

exit 0
