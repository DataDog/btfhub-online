package compression

import (
	"archive/tar"
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"

	gzip "github.com/klauspost/pgzip"
	"github.com/rotisserie/eris"
)

// CompressTarGZ compresses a given input dir into a tar.gz.
func CompressTarGZ(inputDir string) (*bytes.Buffer, error) {
	outputBuffer := &bytes.Buffer{}
	gzipWriter := gzip.NewWriter(outputBuffer)
	tarWriter := tar.NewWriter(gzipWriter)

	// walk through every file in the folder
	err := filepath.Walk(inputDir, func(file string, fi os.FileInfo, _ error) error {
		// generate tar header
		header, err := tar.FileInfoHeader(fi, file)
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
		// if not a dir, write file content
		if !fi.IsDir() {
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
		_ = gzipWriter.Close()
		return nil, eris.Wrap(err, "failed compressing input directory")
	}

	// produce tar
	if err := tarWriter.Close(); err != nil {
		return nil, eris.Wrap(err, "failed finalizing tar")
	}
	// produce gzip
	if err := gzipWriter.Close(); err != nil {
		return nil, eris.Wrap(err, "failed finalizing gz")
	}

	return outputBuffer, nil
}
