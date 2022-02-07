package handlers

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path"

	"github.com/gin-gonic/gin"
	"github.com/rotisserie/eris"

	"github.com/seek-ret/btfhub-online/internal/btfarchive"
	"github.com/seek-ret/btfhub-online/internal/compression"
	"github.com/seek-ret/btfhub-online/internal/datatypes"
)

// RoutesHandler is the implementation for all handlers of the BTFHub online server.
type RoutesHandler struct {
	archive  btfarchive.Archive
	toolsDir string
}

// NewRoutesHandler returns a new instance of the RoutesHandler.
func NewRoutesHandler(archive btfarchive.Archive, toolsDir string) RoutesHandler {
	return RoutesHandler{
		archive:  archive,
		toolsDir: toolsDir,
	}
}

// ListBTFs returns a list of all available BTFs from the archive.
func (routesHandler RoutesHandler) ListBTFs(ginContext *gin.Context) {
	btfs, err := routesHandler.archive.List(ginContext)
	if err != nil {
		_ = ginContext.AbortWithError(http.StatusInternalServerError, err)
		return
	}
	ginContext.JSON(http.StatusOK, btfs)
}

// DownloadBTF receives upon the query variables the BTFRecordIdentifier and download the BTF as is from the acrhive.
func (routesHandler RoutesHandler) DownloadBTF(ginContext *gin.Context) {
	var identifier datatypes.BTFRecordIdentifier
	if err := ginContext.BindQuery(&identifier); err != nil {
		_ = ginContext.AbortWithError(http.StatusBadRequest, err)
		return
	}

	reader, size, err := routesHandler.archive.Download(ginContext, identifier)
	if err != nil {
		_ = ginContext.AbortWithError(http.StatusInternalServerError, err)
		return
	}
	ginContext.DataFromReader(http.StatusOK, size, "application/octet-stream", reader, map[string]string{
		"Content-Description":       "File Transfer",
		"Content-Transfer-Encoding": "binary",
	})
}

// extractBPFToFile tries to read bpf from entry from the request and write it to a file in the given directory.
func extractBPFToFile(ginContext *gin.Context, dir string) (string, error) {
	// Read the BPF binary from the HTTP payload.
	bpfReader, err := ginContext.FormFile("bpf")
	if err != nil {
		return "", eris.Wrap(err, "failed reading BTF from request")
	}

	filePath := path.Join(dir, "bpf.core.o")
	bpfHandle, err := os.Create(filePath)
	if err != nil {
		return "", eris.Wrap(err, "failed creating temporary file for the BTF")
	}
	// no need to remove the file as the directory will be deleted.

	reader, err := bpfReader.Open()
	if err != nil {
		return "", eris.Wrap(err, "failed reading BTF")
	}

	// Write the BPF binary to the temporary file.
	if _, err := io.Copy(bpfHandle, reader); err != nil {
		return "", eris.Wrap(err, "failed copying BTF to temporary file")
	}

	return bpfHandle.Name(), nil
}

// downloadAndExtractBTF tries to download the requested BTF from the archive (as tar.xz file) and extract it.
func (routesHandler RoutesHandler) downloadAndExtractBTF(ginContext *gin.Context, identifier datatypes.BTFRecordIdentifier, dir string) (string, error) {
	// Downloading the BTF locally.
	btfReader, _, err := routesHandler.archive.Download(ginContext, identifier)
	if err != nil {
		return "", eris.Wrap(err, "failed downloading BTF")
	}

	btfsDir := path.Join(dir, "btfs")
	if err := os.MkdirAll(btfsDir, 0755); err != nil {
		return "", eris.Wrap(err, "failed creating temporary directory for BTF")
	}

	if err := compression.DecompressTarXZ(btfsDir, btfReader); err != nil {
		return "", eris.Wrap(err, "failed decompressing BTF")
	}

	return btfsDir, nil
}

// CustomizeBTF wraps generateBTFs to reduce code duplication with CustomizeBTFLegacy.
// Receives the BTF identifier from query parameters and returns the customized BTF for the given BPF.
func (routesHandler RoutesHandler) CustomizeBTF(ginContext *gin.Context) {
	var identifier datatypes.BTFRecordIdentifier
	if err := ginContext.BindQuery(&identifier); err != nil {
		_ = ginContext.AbortWithError(http.StatusInternalServerError, err)
		return
	}

	// Create a temporary directory that will hold the BTFs we generate.
	dir, err := ioutil.TempDir("", "customize-btf")
	if err != nil {
		log.Printf("Failed creating temporary directory for customizing BTF: %+v", err)
		ginContext.AbortWithStatus(http.StatusInternalServerError)
		return
	}
	defer os.RemoveAll(dir)

	bpfFile, err := extractBPFToFile(ginContext, dir)
	if err != nil {
		log.Printf("%+v", err)
		_ = ginContext.AbortWithError(http.StatusInternalServerError, err)
		return
	}

	btfsDir, err := routesHandler.downloadAndExtractBTF(ginContext, identifier, dir)
	if err != nil {
		log.Printf("%+v", err)
		_ = ginContext.AbortWithError(http.StatusInternalServerError, err)
		return
	}

	outputDir := path.Join(dir, "output")
	if err := os.Mkdir(outputDir, 0755); err != nil {
		log.Printf("Failed copy BTF to the temporary file: %+v", err)
		ginContext.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	commandLine := []string{
		"--object", bpfFile,
		"--input", btfsDir,
		"--output", outputDir,
	}
	// Run the btfgen script that gets BPF file path, and a filter for kernels, the script will generate BTF for every
	// kernel in the bucket that matches to the filter.
	// The outcome will be a tar-gz of all the minimized BTFs for the given BPF.
	//nolint:gosec
	command := exec.Command(fmt.Sprintf("%s/bin/btfgen", routesHandler.toolsDir), commandLine...)
	var out bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &out
	command.Stderr = &stderr
	command.Dir = dir
	if err := command.Run(); err != nil {
		log.Printf("Failed creating BTFs for a given BPF due to: %+v", err)
		log.Printf("Output log: %s", stderr.String())
		ginContext.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	compressedOutput, err := compression.CompressTarGZ(outputDir)
	if err != nil {
		log.Printf("Failed compressing results: %+v", err)
		ginContext.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	ginContext.DataFromReader(http.StatusOK, int64(compressedOutput.Len()), "application/octet-stream", compressedOutput, map[string]string{
		"Content-Description":       "File Transfer",
		"Content-Transfer-Encoding": "binary",
	})
}
