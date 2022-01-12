package main

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/seek-ret/btfhub-online/internal/env"
)

const (
	defaultPort = "8080"
)

var (
	toolsDir string
)

func init() {
	var err error
	toolsDir, err = env.GetAbsolutePathFromEnv("TOOLS_DIR")
	if err != nil {
		log.Fatal(err)
	}
}

func generateBTFs(context *gin.Context, filter string) {
	bpfReader, err := context.FormFile("bpf")
	if err != nil {
		context.AbortWithError(http.StatusBadRequest, err)
		return
	}

	bpfFile, err := ioutil.TempFile("", "bpf")
	if err != nil {
		context.AbortWithError(http.StatusBadRequest, err)
		return
	}
	defer os.Remove(bpfFile.Name())
	reader, err := bpfReader.Open()
	if err != nil {
		context.AbortWithError(http.StatusBadRequest, err)
		return
	}
	if _, err := io.Copy(bpfFile, reader); err != nil {
		context.AbortWithError(http.StatusBadRequest, err)
		return
	}

	dir, err := ioutil.TempDir("", "btf")
	if err != nil {
		context.JSON(http.StatusInternalServerError, err)
		return
	}
	defer os.RemoveAll(dir)

	//nolint:gosec
	command := exec.Command(fmt.Sprintf("%s/btfgen.sh", toolsDir), bpfFile.Name(), filter)
	var out bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &out
	command.Stderr = &stderr
	command.Dir = dir
	if err := command.Run(); err != nil {
		log.Printf("Failed formatting the code due to: %+v", err)
		log.Printf("Output log: %s", stderr.String())
		context.JSON(http.StatusInternalServerError, err)
		return
	}

	//Seems these headers needed for some browsers (for example without these headers Chrome will download files as txt)
	context.Header("Content-Description", "File Transfer")
	context.Header("Content-Transfer-Encoding", "binary")
	context.Header("Content-Disposition", "attachment; filename=btfs.tar.gz")
	context.Header("Content-Type", "application/octet-stream")
	context.File(filepath.Join(dir, "btfs.tar.gz"))
}

func generateSingleBTF(context *gin.Context) {
	kernelName := context.Query("kernel_name")
	if kernelName == "" {
		context.AbortWithStatusJSON(http.StatusBadRequest, "missing kernel_name query param")
		return
	}

	kernelName = strings.Replace(kernelName, "/", "\\/", -1)
	kernelName = strings.Replace(kernelName, ".", "\\.", -1)
	kernelName = strings.Replace(kernelName, "-", "\\-", -1)
	// Removing the old wrapping from the old sniffer.
	kernelName = strings.Replace(kernelName, "*", "", -1)
	generateBTFs(context, kernelName)
}

func generateBTFHub(context *gin.Context) {
	generateBTFs(context, "")
}

func main() {
	engine := gin.New()

	engine.Use(gin.LoggerWithFormatter(func(param gin.LogFormatterParams) string {
		return fmt.Sprintf("%s - [%s] \"%s %s %s %d %s \"%s\" %s\"\n",
			param.ClientIP,
			param.TimeStamp.Format(time.RFC1123),
			param.Method,
			param.Path,
			param.Request.Proto,
			param.StatusCode,
			param.Latency,
			param.Request.UserAgent(),
			param.ErrorMessage,
		)
	}))
	engine.Use(gin.Recovery())
	engine.POST("/generate", generateSingleBTF)
	engine.POST("/generate-hub", generateBTFHub)

	port := os.Getenv("PORT")
	if port == "" {
		port = defaultPort
	}

	fmt.Printf("listening on 0.0.0.0:%s\n", port)
	if err := engine.Run(fmt.Sprintf("0.0.0.0:%s", port)); err != nil {
		log.Fatal(err)
	}
}
