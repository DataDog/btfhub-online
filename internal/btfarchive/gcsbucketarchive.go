package btfarchive

import (
	"fmt"
	"io"
	"strings"

	"cloud.google.com/go/storage"
	"github.com/rotisserie/eris"
	"golang.org/x/net/context"
	"google.golang.org/api/iterator"

	"github.com/seek-ret/btfhub-online/internal/datatypes"
)

const (
	btfSuffix = ".btf.tar.xz"
)

// GCSBucketArchive is an archive that uses GCS bucket.
type GCSBucketArchive struct {
	bucket *storage.BucketHandle
}

// NewGCSBucketArchive creates a new GCS bucket archive for the input bucket name.
func NewGCSBucketArchive(bucketName string) (Archive, error) {
	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, eris.Wrap(err, "failed initializing gcp storage client")
	}

	return &GCSBucketArchive{
		bucket: client.Bucket(bucketName),
	}, nil
}

func (archive GCSBucketArchive) List(ctx context.Context) ([]datatypes.BTFRecordIdentifier, error) {
	iter := archive.bucket.Objects(ctx, nil)
	res := make([]datatypes.BTFRecordIdentifier, 0)
	for {
		attrs, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, eris.Wrap(err, "failed listing objects in the bucket")
		}

		if strings.HasSuffix(attrs.Name, btfSuffix) {
			attributeName := strings.TrimSuffix(attrs.Name, btfSuffix)
			components := strings.Split(attributeName, "/")
			// The format should be <distro>/<distro version>/<arch>/<kernel version>.btf.tar.xz
			if len(components) != 4 {
				continue
			}
			res = append(res, datatypes.BTFRecordIdentifier{
				Distribution:        components[0],
				DistributionVersion: components[1],
				Arch:                components[2],
				KernelVersion:       components[3],
			})
		}
	}

	return res, nil
}

func (archive GCSBucketArchive) Download(ctx context.Context, identifier datatypes.BTFRecordIdentifier) (io.Reader, int64, error) {
	expectedPath := fmt.Sprintf("%s/%s/%s/%s%s", identifier.Distribution, identifier.DistributionVersion, identifier.Arch, identifier.KernelVersion, btfSuffix)
	obj := archive.bucket.Object(expectedPath)
	if obj == nil {
		return nil, 0, eris.Errorf("didn't find a btf for %v", identifier)
	}
	reader, err := obj.NewReader(ctx)
	if err != nil {
		return nil, 0, eris.Wrapf(err, "failed creating a reader of the BTF for %v", identifier)
	}
	attr, err := obj.Attrs(ctx)
	if err != nil {
		return nil, 0, eris.Wrapf(err, "failed getting attributes of the BTF for %v", identifier)
	}

	return reader, attr.Size, nil
}
