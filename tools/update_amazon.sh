#!/bin/bash

# Downloading miror list file which holds the current address of the ftp server
wget https://amazonlinux-2-repos-us-east-2.s3.dualstack.us-east-2.amazonaws.com/2/core/latest/debuginfo/x86_64/mirror.list
# Downloading the latest compressed packages list
wget "$(head -1 mirror.list)/repodata/primary.sqlite.gz"
rm -f mirror.list
# Unzip the packages list
gzip -d primary.sqlite.gz
rm -f primary.sqlite.gz
# Extracting the kernel packages into a file
packages=$(sqlite3 primary.sqlite "select location_href FROM packages WHERE name like 'kernel-debuginfo%' and name not like '%common%'" | sed 's#\.\./##g')
# Creating a file with only the kernel versions
echo $packages | tr "/" " " | awk '{print $3}' | sed 's/kernel-debuginfo-//g' | sed 's/.rpm//g' | sort > packages_names
# Getting all kernel versions that we already produced them a BTF file
gsutil ls gs://btfhub/amzn/2/x86_64/ | sed 's,gs://btfhub/amzn/2/x86_64/,,g' | sed 's/.btf.tar.xz//g' | sed 's/.failed//g' | sort > gs_names
# Getting the new kernels that does not have a BTF file
new_packages=$(comm -23 packages_names gs_names)
rm -f gs_names packages_names primary.sqlite
# For every new kernel
for package in $new_packages; do
    url=$(echo $packages | grep $package)
    filename=$(basename "${url}")
    # shellcheck disable=SC2001
    version=$(echo "${filename}" | sed 's:kernel-debuginfo-\(.*\).rpm:\1:g')

    echo URL: "${url}"
    echo FILENAME: "${filename}"
    echo VERSION: "${version}"

    # Download kernel from FTP server
    axel -4 -n 8 "http://amazonlinux.us-east-1.amazonaws.com/${url}"
    mv "${filename}" "${version}.rpm"
    if [ ! -f "${version}.rpm" ]; then
      echo "WARN: ${version}.rpm could not be downloaded"
      continue
    fi

    # Extract the vmlinux location from the kernel image
    vmlinux=.$(rpmquery -qlp "${version}.rpm" 2>&1 | grep vmlinux)
    echo "INFO: extracting vmlinux from: ${version}.rpm"
    # Extract the vmlinux into a file
    rpm2cpio "${version}.rpm" | cpio --to-stdout -i "${vmlinux}" > "./${version}.vmlinux" || \
    {
        echo "WARN: could not deal with ${version}, cleaning and moving on..."
        rm -rf "${version}.rpm"
        rm -rf "${version}.vmlinux"
        touch "${version}.failed"
        gsutil cp "${version}.failed" gs://btfhub/amzn/2/x86_64/"${version}.failed"
        continue
    }

    # Generate BTF raw file from DWARF data
    echo "INFO: generating BTF file: ${version}.btf"
    pahole --btf_encode_detached "${version}.btf" "${version}.vmlinux"
    # Compress the BTF
    tar cvfJ "./${version}.btf.tar.xz" "${version}.btf"

    rm "${version}.rpm"
    rm "${version}.btf"
    rm "${version}.vmlinux"
    # Move the compress BTF to the cloud
    gsutil cp ./${version}.btf.tar.xz gs://btfhub/amzn/2/x86_64/${version}.btf.tar.xz
    rm ${version}.btf.tar.xz
done

echo "Done"
rm -f packages

exit 0
