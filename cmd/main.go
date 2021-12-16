package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"google.golang.org/api/iterator"

	"cloud.google.com/go/storage"
	"github.com/gin-gonic/gin"
)

var (
	archiveDir string
	toolsDir   string
	distros    = map[string]struct{}{
		"amazon": {},
		"debian": {},
		"ubuntu": {},
		"centos": {},
		"fedora": {},
	}
)

const (
	defaultPort = "8080"
)

func getAbsolutePathFromEnv(env string, createIfMissing bool) string {
	dirEnv := os.Getenv(env)
	if dirEnv == "" {
		log.Panicf("%s is empty", env)
	}
	var err error
	dirPath, err := filepath.Abs(dirEnv)
	if err != nil {
		log.Fatal(err)
	}
	_, err = os.Stat(dirPath)
	if err != nil {
		if createIfMissing {
			if err := os.Mkdir(dirPath, 0755); err != nil {
				log.Fatal(err)
			}
		} else {
			log.Fatal(err)
		}
	}

	return dirPath
}

func downloadHub(targetDir string) error {
	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}

	btfhubBucket := client.Bucket("btfhub")
	iter := btfhubBucket.Objects(ctx, nil)
	wg := sync.WaitGroup{}
	for {
		attrs, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			log.Printf("Bucket(btfhub).Objects: %v", err)
			continue
		}
		localFilePath := filepath.Join(targetDir, attrs.Name)
		localFile, err := os.Stat(localFilePath)
		if err == nil && localFile.Size() == attrs.Size {
			// Already exists
			continue
		}
		reader, err := btfhubBucket.Object(attrs.Name).NewReader(ctx)
		if err != nil {
			log.Printf("1Bucket(btfhub).Objects: %v", err)
			continue
		}

		wg.Add(1)
		go func() {
			defer wg.Done()
			currentDir := filepath.Dir(localFilePath)
			os.MkdirAll(currentDir, 0755)
			localFileHandle, err := os.Create(localFilePath)
			if err != nil {
				log.Printf("failed creating %s due to: %v", localFilePath, err)
				return
			}

			if _, err := io.Copy(localFileHandle, reader); err != nil {
				log.Printf("io.Copy: %v", err)
				return
			}

			if err = localFileHandle.Close(); err != nil {
				log.Printf("f.Close: %v", err)
				return
			}
		}()

	}

	wg.Wait()
	return nil
}

func init() {
	archiveDir = getAbsolutePathFromEnv("ARCHIVE_DIR", true)
	toolsDir = getAbsolutePathFromEnv("TOOLS_DIR", false)

	if err := downloadHub(archiveDir); err != nil {
		panic(err)
	}
}

func updateHandlerInternal() {
	wg := sync.WaitGroup{}
	for distro := range distros {
		wg.Add(1)
		distro := distro
		go func() {
			defer wg.Done()
			dir, err := ioutil.TempDir("", distro)
			if err != nil {
				log.Fatal(err)
			}
			defer os.RemoveAll(dir)
			command := exec.Command(fmt.Sprintf("%s/update_%s.sh", toolsDir, distro))
			var out bytes.Buffer
			var stderr bytes.Buffer
			command.Stdout = &out
			command.Stderr = &stderr
			command.Dir = dir
			if err := command.Run(); err != nil {
				log.Printf("Failed formatting the code due to: %+v", err)
				log.Printf("Output log: %s", stderr.String())
			}
		}()
	}

	wg.Wait()
	if err := downloadHub(archiveDir); err != nil {
		log.Printf("Failed downloading updated hub due to: %v", err)
	}
}

func updateHandler(context *gin.Context) {
	go updateHandlerInternal()
	context.Status(http.StatusOK)
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
	command := exec.Command(fmt.Sprintf("%s/btfgen.sh", toolsDir), archiveDir, bpfFile.Name(), filter)
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

	//Seems this headers needed for some browsers (for example without this headers Chrome will download files as txt)
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

	generateBTFs(context, fmt.Sprintf("*%s*", kernelName))
}

func generateBTFHub(context *gin.Context) {
	generateBTFs(context, "*")
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
	engine.POST("/update", updateHandler)
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
