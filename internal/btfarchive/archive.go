package btfarchive

import (
	"context"
	"io"

	"github.com/seek-ret/btfhub-online/internal/datatypes"
)

// Archive is an interface for all implementation of archives (GCP bucket, local directory, S3, etc.)
type Archive interface {
	// List returns all BTF identifiers in the archive.
	List(context.Context) ([]datatypes.BTFRecordIdentifier, error)

	// Download returns a reader of the BTF.
	Download(context.Context, datatypes.BTFRecordIdentifier) (io.Reader, int64, error)
}
