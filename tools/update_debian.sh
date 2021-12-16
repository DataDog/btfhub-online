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

    wget ${repository}/dists/${debianver}/main/binary-amd64/Packages.gz -O ${debianver}.gz
    wget ${repository}/dists/${debianver}-updates/main/binary-amd64/Packages.gz -O ${debianver}-updates.gz

    [ ! -f ${debianver}.gz ] && exiterr "no ${debianver}.gz packages file found"
    [ ! -f ${debianver}-updates.gz ] && exiterr "no ${debianver}-updates.gz packages file found"

    gzip -d ${debianver}.gz
    grep -E '^(Package|Filename):' ${debianver} | grep --no-group-separator -A1 -E "^Package: ${regex}" > packages
    gzip -d ${debianver}-updates.gz
    grep -E '^(Package|Filename):' ${debianver}-updates | grep --no-group-separator -A1 -E "Package: ${regex}" >> packages

    packages_sorted=$(grep "Package:" packages | sed 's:Package\: ::g' | sort)
    echo $packages_sorted | sed 's:linux-image-::g' | sed 's:-dbgsym.*::g' | sed 's:unsigned-::g' | sort > packages_version
    gsutil ls gs://btfhub/debian/${debian_number}/x86_64/ | sed "s,gs://btfhub/debian/${debian_number}/x86_64/,,g" | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort > gs_names
    new_packages=$(comm -23 packages_version gs_names)
    rm -f packages ${debianver} ${debianver}-updates gs_names packages_version
    for package in $new_packages; do
	    filepath=$(grep -A1 "${package}" packages | grep -v "^Package: " | sed 's:Filename\: ::g')
	    url="${repository}/${filepath}"
	    filename=$(basename "${filepath}")
	    version=$(echo "${filename}" | sed 's:linux-image-::g' | sed 's:-dbgsym.*::g' | sed 's:unsigned-::g')

	    echo URL: "${url}"
	    echo FILEPATH: "${filepath}"
	    echo FILENAME: "${filename}"
	    echo VERSION: "${version}"

	    if [ ! -f "${version}.ddeb" ]; then
	    	curl -4 "${url}" -o ${version}.ddeb
	    	if [ ! -f "${version}.ddeb" ]
	    	then
	    		echo "WARN: ${version}.ddeb could not be downloaded"
	    		continue
	    	fi
	    fi

	    dpkg --fsys-tarfile "${version}.ddeb" | tar xvf - "./usr/lib/debug/boot/vmlinux-${version}" || \
	    {
	        echo "WARN: could not deal with ${version}, cleaning and moving on..."
	        rm -rf "${version}.ddeb"
		      touch "${version}.failed"
          gsutil cp ./${version}.failed gs://btfhub/debian/${debian_number}/x86_64/${version}.failed
          rm "${version}.failed"
	        continue
	    }

	    mv "./usr/lib/debug/boot/vmlinux-${version}" "./${version}.vmlinux" || \
	    {
	        echo "WARN: could not rename vmlinux ${version}, cleaning and moving on..."
	        rm -rf "${version}.ddeb"
		      touch "${version}.failed"
          gsutil cp ./${version}.failed gs://btfhub/debian/${debian_number}/x86_64/${version}.failed
          rm "${version}.failed"
	        continue
      }

	    rm -rf "./usr/lib/debug/boot"

	    pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
	    tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"

      rm "${version}.ddeb"
	    rm "${version}.btf"
	    rm "${version}.vmlinux"
      gsutil cp ./${version}.btf.tar.xz gs://btfhub/debian/${debian_number}/x86_64/${version}.btf.tar.xz
      rm "${version}.btf.tar.xz"

    done


done

exit 0
