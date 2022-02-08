package compression

import (
	"archive/tar"
	"bytes"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/rotisserie/eris"
	"github.com/ulikunitz/xz"
)

// General explanation about tar.xz https://linuxize.com/post/how-to-extract-unzip-tar-xz-file/

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

// CompressTarXZ compresses a given input dir into a tar.xz.
func CompressTarXZ(inputDir string) (*bytes.Buffer, error) {
	outputBuffer := &bytes.Buffer{}
	xzWriter, err := xz.NewWriter(outputBuffer)
	if err != nil {
		return nil, err
	}
	tarWriter := tar.NewWriter(xzWriter)

	// iterate all files in the target directory
	err = filepath.WalkDir(inputDir, func(file string, dirEntry fs.DirEntry, _ error) error {
		fileInfo, err := dirEntry.Info()
		if err != nil {
			return err
		}
		// generate tar header
		header, err := tar.FileInfoHeader(fileInfo, file)
		if err != nil {
			return err
		}

		// Must provide real name. Removing the directory from the full path.
		// (see https://golang.org/src/archive/tar/common.go?#L626)
		header.Name = filepath.ToSlash(strings.TrimPrefix(file, inputDir))

		// write header
		if err := tarWriter.WriteHeader(header); err != nil {
			return err
		}
		// if not a dir, write the file content
		if !fileInfo.IsDir() {
			data, err := os.Open(file)
			if err != nil {
				return err
			}
			if _, err := io.Copy(tarWriter, data); err != nil {
				return err
			}
		}
		return nil
	})

	if err != nil {
		_ = tarWriter.Close()
		_ = xzWriter.Close()
		return nil, eris.Wrap(err, "failed compressing input directory")
	}

	// produce tar
	if err := tarWriter.Close(); err != nil {
		return nil, eris.Wrap(err, "failed finalizing tar")
	}
	// produce gzip
	if err := xzWriter.Close(); err != nil {
		return nil, eris.Wrap(err, "failed finalizing xz")
	}

	return outputBuffer, nil
}
