# BTFHub online
BTFHub online is the online version of the great [BTFHub project](https://github.com/aquasecurity/btfhub).
The purpose of the online version is to make it easier for developers to fetch their relevant BTF for their BPF binary.

The project will allow you to be "forward compatible" with new minor versions or patches of your kernel being released.

# Visual Diagram
![](docs/BTFHubOnline.jpg)

# Mode of operation
While developing your eBPF module, use our SDKs or the api documentation to dynamically pull the BTF that suites
your eBPF module.

# Examples
TBD

# Credits

Thanks to:

* Aqua Security for creating [BTFHub](https://github.com/aquasecurity/btfhub).