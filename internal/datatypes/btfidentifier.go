package datatypes

// BTFRecordIdentifier uniquely identifies a BTF in the archive.
type BTFRecordIdentifier struct {
	Distribution        string `json:"distribution" form:"distribution"`
	DistributionVersion string `json:"distribution_version" form:"distribution_version"`
	KernelVersion       string `json:"kernel_version" form:"kernel_version"`
	Arch                string `json:"arch" form:"arch"`
}
