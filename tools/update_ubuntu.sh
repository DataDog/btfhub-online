#!/bin/bash -x

repository="http://ddebs.ubuntu.com"

for ubuntuver in bionic focal; do
    case "${ubuntuver}" in
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

    gs_names=$(gsutil ls gs://btfhub/ubuntu/${ubuntu_number}/x86_64/ | sed "s,gs://btfhub/ubuntu/${ubuntu_number}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort)

    wget http://ddebs.ubuntu.com/dists/${ubuntuver}/main/binary-amd64/Packages -O ${ubuntuver}
    wget http://ddebs.ubuntu.com/dists/${ubuntuver}-updates/main/binary-amd64/Packages -O ${ubuntuver}-updates

    [ ! -f ${ubuntuver} ] && exiterr "no ${ubuntuver} packages file found"
    [ ! -f ${ubuntuver}-updates ] && exiterr "no ${ubuntuver}-updates packages file found"

    grep -E '^(Package|Filename):' ${ubuntuver} | grep --no-group-separator -A1 -E "^Package: ${regex}" > packages
    grep -E '^(Package|Filename):' ${ubuntuver}-updates | grep --no-group-separator -A1 -E "Package: ${regex}" >> packages
    rm ${ubuntuver}
    rm ${ubuntuver}-updates

    grep "Package:" packages | sed 's:Package\: ::g' | sort | while read -r package; do

        filepath=$(grep -A1 "${package}" packages | grep -v "^Package: " | sed 's:Filename\: ::g')
        url="${repository}/${filepath}"
        filename=$(basename "${filepath}")
        version=$(echo "${filename}" | sed 's:linux-image-::g' | sed 's:-dbgsym.*::g' | sed 's:unsigned-::g')

        if [[ "${gs_names[*]}" =~ ${version} ]]; then
            echo "INFO: file ${version}.btf already exists"
            continue
        fi

        echo URL: "${url}"
        echo FILEPATH: "${filepath}"
        echo FILENAME: "${filename}"
        echo VERSION: "${version}"

        axel -4 -n 16 "${url}" -o ${version}.ddeb
        if [ ! -f "${version}.ddeb" ]
        then
          echo "WARN: ${version}.ddeb could not be downloaded"
          continue
        fi

        # extract vmlinux file from ddeb package
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

        pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
        tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"
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
