package main

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/alexflint/go-arg"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	metrics "github.com/slok/go-http-metrics/metrics/prometheus"
	"github.com/slok/go-http-metrics/middleware"
	ginmiddleware "github.com/slok/go-http-metrics/middleware/gin"

	"github.com/seek-ret/btfhub-online/internal/btfarchive"
	"github.com/seek-ret/btfhub-online/internal/handlers"
	"github.com/seek-ret/btfhub-online/internal/path"
)

// args is the arguments to the server. Each of the arguments can be supplied via environment variable or command line.
var args struct {
	BucketName  string `arg:"-b,env:BUCKET_NAME,required"`
	ToolsDir    string `arg:"-t,env:TOOLS_DIR,required"`
	Port        string `arg:"-p,env:PORT" default:"8080"`
	MetricsPort string `arg:"-m,env:METRICS_PORT"`
}

func main() {
	arg.MustParse(&args)

	toolsDir, err := path.GetAbsolutePath(args.ToolsDir)
	if err != nil {
		log.Fatalf("Failed to find %s due to: %+v", args.ToolsDir, err)
	}

	archive, err := btfarchive.NewGCSBucketArchive(args.BucketName)
	if err != nil {
		log.Fatalf("Failed initialize GCP bucket %q archive due to: %+v", args.BucketName, err)
	}

	routesHandler := handlers.NewRoutesHandler(archive, toolsDir)

	// Create our middleware.
	prometheusMiddleware := middleware.New(middleware.Config{
		Recorder: metrics.NewRecorder(metrics.Config{}),
	})
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
	engine.Use(ginmiddleware.Handler("", prometheusMiddleware))

	apiRouterGroup := engine.Group("/api")
	v1RouterGroup := apiRouterGroup.Group("/v1")
	v1RouterGroup.POST("/customize", routesHandler.CustomizeBTF)
	v1RouterGroup.GET("/download", routesHandler.DownloadBTF)
	v1RouterGroup.GET("/list", routesHandler.ListBTFs)

	// Legacy of the beta release
	engine.POST("/generate", routesHandler.CustomizeBTFLegacy)
	engine.GET("/list", routesHandler.ListBTFsLegacy)

	// Serve our metrics.
	if args.MetricsPort != "" {
		go func() {
			metricsAddress := fmt.Sprintf("0.0.0.0:%s", args.MetricsPort)
			log.Printf("Metrics listening at %s", metricsAddress)
			if err := http.ListenAndServe(metricsAddress, promhttp.Handler()); err != nil {
				log.Panicf("Error while serving metrics: %s", err)
			}
		}()
	}

	fmt.Printf("listening on 0.0.0.0:%s\n", args.Port)
	if err := engine.Run(fmt.Sprintf("0.0.0.0:%s", args.Port)); err != nil {
		log.Fatal(err)
	}
}
