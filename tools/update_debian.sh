#!/bin/bash

repository="http://ftp.debian.org/debian"

regex="linux-image-[4-9]+\.[0-9]+\.[0-9].*amd64-dbg"
for debianver in stretch buster bullseye; do
    case "${debianver}" in
    "stretch")
        debian_number=9
        ;;
    "buster")
        debian_number=10
        ;;
    "bullseye")
        debian_number=11
        ;;
    *)
    continue
        ;;
    esac

    # Extracting from the remote bucket the kernel versions we already handled (either successfully or failed).
    # Thus we will look for kernel we didn't handle it, so we will reduce run time of the script.
    # The line gets a list of all kernels in the remote bucket and extracts the kernel version from their name.
    gs_names=$(gsutil ls gs://btfhub/debian/${debian_number}/x86_64/ | sed "s,gs://btfhub/debian/${debian_number}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

    wget ${repository}/dists/${debianver}/main/binary-amd64/Packages.gz -O ${debianver}.gz
    if [ ${debian_number} -lt 11 ]; then
        wget ${repository}/dists/${debianver}-updates/main/binary-amd64/Packages.gz -O ${debianver}-updates.gz
    fi

    [ ! -f ${debianver}.gz ] && exiterr "no ${debianver}.gz packages file found"
    if [ ${debian_number} -lt 11 ]; then
        [ ! -f ${debianver}-updates.gz ] && exiterr "no ${debianver}-updates.gz packages file found"
    fi

    gzip -d ${debianver}.gz
    grep -E '^(Package|Filename):' ${debianver} | grep --no-group-separator -A1 -E "^Package: ${regex}" > packages
    if [ ${debian_number} -lt 11 ]; then
        gzip -d ${debianver}-updates.gz
        grep -E '^(Package|Filename):' ${debianver}-updates | grep --no-group-separator -A1 -E "Package: ${regex}" >> packages
    fi
    rm -f ${debianver} ${debianver}-updates

    # Iterating over packages names. We look for all lines starting with `Package: ` in the packages file.
    # Then we strip the beginning of `Package: ` from the line to obtain the package name only.
    # Then we sort the packages and iterating over them.
    grep "Package:" packages | sed 's:Package\: ::g' | sort | while read -r package; do

        filepath=$(grep -A1 "${package}" packages | grep -v "^Package: " | sed 's:Filename\: ::g')
        url="${repository}/${filepath}"
        filename=$(basename "${filepath}")
        version=$(echo "${filename}" | sed 's:linux-image-::g' | sed 's:-dbg.*::g' | sed 's:unsigned-::g')

        if [[ "${gs_names[*]}" =~ ${version} ]]; then
            echo "INFO: file ${version}.btf already exists"
            continue
        fi

        echo URL: "${url}"
        echo FILEPATH: "${filepath}"
        echo FILENAME: "${filename}"
        echo VERSION: "${version}"

        axel -4 -n 16 "${url}" -o ${version}.ddeb
        if [ ! -f "${version}.ddeb" ]; then
            echo "WARN: ${version}.ddeb could not be downloaded"
            continue
        fi

        # extract vmlinux file from ddeb package
        dpkg --fsys-tarfile "${version}.ddeb" | tar xvf - "./usr/lib/debug/boot/vmlinux-${version}" || \
        {
            echo "WARN: could not deal with ${version}, cleaning and moving on..."
            rm -rf "./usr"
            rm -rf "${version}.ddeb"
            gsutil cp ./${version}.failed gs://btfhub/debian/${debian_number}/x86_64/${version}.failed
            continue
        }

        mv "./usr/lib/debug/boot/vmlinux-${version}" "./${version}.vmlinux" || \
        {
            echo "WARN: could not rename vmlinux ${version}, cleaning and moving on..."
            rm -rf "./usr"
            rm -rf "${version}.ddeb"
            gsutil cp ./${version}.failed gs://btfhub/debian/${debian_number}/x86_64/${version}.failed
            continue

        }

        rm -rf "./usr/lib/debug/boot"

        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
        gsutil cp ./${version}.btf.tar.xz gs://btfhub/debian/${debian_number}/x86_64/${version}.btf.tar.xz

        rm "${version}.ddeb"
        rm "${version}.btf"
        rm "${version}.vmlinux"
        rm "${version}.btf.tar.xz"
    done

    rm -f packages
done

echo "Done"

exit 0
