package compression

import (
	"archive/tar"
	"io"
	"os"
	"path/filepath"

	"github.com/rotisserie/eris"
	"github.com/ulikunitz/xz"
)

// extractFileHelper is a helper function that copies a single file from the tar reader into a real location on disk.
func extractFileHelper(target string, fileMode int64, tarReader io.Reader) error {
	f, err := os.OpenFile(target, os.O_CREATE|os.O_RDWR, os.FileMode(fileMode))
	if err != nil {
		return eris.Wrapf(err, "failed creating file %q", target)
	}
	defer f.Close()

	if _, err := io.Copy(f, tarReader); err != nil {
		return eris.Wrapf(err, "failed writing compressed file content %q", target)
	}
	return nil
}

// DecompressTarXZ extracts the content of the input reader into a destination directory.
func DecompressTarXZ(dstDir string, inputReader io.Reader) error {
	xzReader, err := xz.NewReader(inputReader)
	if err != nil {
		return eris.Wrap(err, "failed creating xz reader")
	}

	tarReader := tar.NewReader(xzReader)

	for {
		header, err := tarReader.Next()

		switch {
		// if no more files are found return
		case err == io.EOF:
			return nil

		// return any other error
		case err != nil:
			return eris.Wrap(err, "failed iterating over the given tar")

		// if the header is nil, just skip it (not sure how this happens)
		case header == nil:
			continue
		}

		// the target location where the dir/file should be created
		target := filepath.Join(dstDir, header.Name)

		// check the file type
		switch header.Typeflag {
		// if it is a dir and it doesn't exist create it
		case tar.TypeDir:
			if _, err := os.Stat(target); err != nil {
				if err := os.MkdirAll(target, 0755); err != nil {
					return eris.Wrapf(err, "failed creating dir %q", target)
				}
			}

		// if it's a file - create it
		case tar.TypeReg:
			if err := extractFileHelper(target, header.Mode, tarReader); err != nil {
				return err
			}
		}
	}
}
