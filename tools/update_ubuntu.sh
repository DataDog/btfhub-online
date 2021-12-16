#!/bin/bash

repository="http://ddebs.ubuntu.com"

for ubuntuver in bionic focal; do
    case "${ubuntuver}" in
    "bionic")
        regex="(linux-image-unsigned-(4.15.0|5.4.0)-.*-(generic|azure)-dbgsym|linux-image-(4.15.0|5.4.0)-.*-aws-dbgsym)"
        ubuntu_number=18.04
        ;;
    "focal")
        regex="(linux-image-unsigned-(5.4.0|5.8.0|5.11.0)-.*-(generic|azure)-dbgsym|linux-image-(5.4.0|5.8.0|5.11.0)-.*-aws-dbgsym)"
        ubuntu_number=20.04
        ;;
    *)
    continue
        ;;
    esac

    wget ${repository}/dists/${ubuntuver}/main/binary-amd64/Packages -O ${ubuntuver}
    wget ${repository}/dists/${ubuntuver}-updates/main/binary-amd64/Packages -O ${ubuntuver}-updates

    [ ! -f ${ubuntuver} ] && exiterr "no ${ubuntuver} packages file found"
    [ ! -f ${ubuntuver}-updates ] && exiterr "no ${ubuntuver}-updates packages file found"

    grep -E '^(Package|Filename):' ${ubuntuver} | grep --no-group-separator -A1 -E "^Package: ${regex}" > packages
    grep -E '^(Package|Filename):' ${ubuntuver}-updates | grep --no-group-separator -A1 -E "Package: ${regex}" >> packages

    packages_sorted=$(grep "Package:" packages | sed 's:Package\: ::g' | sort)
    echo $packages_sorted | sed 's:linux-image-::g' | sed 's:-dbgsym.*::g' | sed 's:unsigned-::g' | sort > packages_version
    gsutil ls gs://btfhub/ubuntu/${ubuntu_number}/x86_64/ | sed "s,gs://btfhub/ubuntu/${ubuntu_number}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort > gs_names
    new_packages=$(comm -23 packages_version gs_names)
    rm -f packages ${ubuntuver} ${ubuntuver}-updates gs_names packages_version
    for package in $new_packages; do
	    filepath=$(grep -A1 "${package}" packages | grep -v "^Package: " | sed 's:Filename\: ::g')
	    url="${repository}/${filepath}"
	    filename=$(basename "${filepath}")
	    version=$(echo "${filename}" | sed 's:linux-image-::g' | sed 's:-dbgsym.*::g' | sed 's:unsigned-::g')

	    if [ -f "${version}.btf.tar.xz" ] || [ -f "${version}.failed" ]; then
	    	continue
	    fi

	    echo URL: "${url}"
	    echo FILEPATH: "${filepath}"
	    echo FILENAME: "${filename}"
	    echo VERSION: "${version}"


	    if [ ! -f "${version}.ddeb" ]; then
	    	curl -4 "${url}" -o ${version}.ddeb
	    	if [ ! -f "${version}.ddeb" ]
	    	then
	    		warn "${version}.ddeb could not be downloaded"
	    		continue
	    	fi
	    fi

	    dpkg --fsys-tarfile "${version}.ddeb" | tar xvf - "./usr/lib/debug/boot/vmlinux-${version}" || \
	    {
	        warn "could not deal with ${version}, cleaning and moving on..."
	        rm -rf "${version}.ddeb"
		      touch "${version}.failed"
          gsutil cp ./${version}.failed gs://btfhub/ubuntu/${ubuntu_number}/x86_64/${version}.failed
          rm
	        continue
	    }

	    mv "./usr/lib/debug/boot/vmlinux-${version}" "./${version}.vmlinux" || \
	    {
	        warn "could not rename vmlinux ${version}, cleaning and moving on..."
	        rm -rf "${version}.ddeb"
		      touch "${version}.failed"
          gsutil cp ./${version}.failed gs://btfhub/ubuntu/${ubuntu_number}/x86_64/${version}.failed
	        continue
      }

	    rm -rf "./usr/lib/debug/boot"

	    pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
	    tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"

      rm "${version}.ddeb"
	    rm "${version}.btf"
	    rm "${version}.vmlinux"
      gsutil cp ./${version}.btf.tar.xz gs://btfhub/ubuntu/${ubuntu_number}/x86_64/${version}.btf.tar.xz
	    rm "${version}.btf.tar.xz"

    done
done

exit 0
