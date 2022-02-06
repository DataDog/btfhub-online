package main

import (
	"fmt"
	"log"
	"sort"
	"time"

	"github.com/alexflint/go-arg"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/heptiolabs/healthcheck"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/prometheus/client_golang/prometheus/push"
	metrics "github.com/slok/go-http-metrics/metrics/prometheus"
	"github.com/slok/go-http-metrics/middleware"
	ginmiddleware "github.com/slok/go-http-metrics/middleware/gin"

	"github.com/seek-ret/btfhub-online/internal/btfarchive"
	"github.com/seek-ret/btfhub-online/internal/handlers"
	"github.com/seek-ret/btfhub-online/internal/path"
)

// args is the arguments to the server. Each of the arguments can be supplied via environment variable or command line.
var args struct {
	BucketName            string `arg:"-b,env:BUCKET_NAME,required"`
	ToolsDir              string `arg:"-t,env:TOOLS_DIR,required"`
	Port                  string `arg:"-p,env:PORT" default:"8080"`
	DisableMonitoring     bool   `arg:"--no-monitoring,env:NO_MONITORING" default:"false"`
	PrometheusPushGateway string `arg:"--push-gateway,env:PUSH_GATEWAY"`
}

const (
	prometheusPushGatewayJobName = "btfhub-online-push"
)

func pushPrometheusMetrics(gateway string, registry *prometheus.Registry) {
	for {
		if err := push.New(gateway, prometheusPushGatewayJobName).Gatherer(registry).Push(); err != nil {
			log.Printf("ERROR: failed pushing prometheus metrics due to: %+v", err)
		}
		time.Sleep(time.Minute)
	}
}

func printAllRoutes(engine *gin.Engine) {
	fmt.Println("Routes: ")
	routes := engine.Routes()
	sort.Slice(routes, func(i, j int) bool {
		return routes[i].Path < routes[j].Path
	})
	for _, route := range routes {
		fmt.Printf("  %-6s %-25s\n", route.Method, route.Path)
	}
}

func setupEngine(registry *prometheus.Registry) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
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

	metricsCfg := metrics.Config{
		Registry: registry,
	}
	prometheusMiddleware := middleware.New(middleware.Config{
		Recorder: metrics.NewRecorder(metricsCfg),
		Service:  fmt.Sprintf("btfhub-online-%s", uuid.NewString()),
	})
	engine.Use(ginmiddleware.Handler("", prometheusMiddleware))

	return engine
}

func addRoutes(engine *gin.Engine, routesHandler handlers.RoutesHandler) {
	apiRouterGroup := engine.Group("/api")
	v1RouterGroup := apiRouterGroup.Group("/v1")
	v1RouterGroup.POST("/customize", routesHandler.CustomizeBTF)
	v1RouterGroup.GET("/download", routesHandler.DownloadBTF)
	v1RouterGroup.GET("/list", routesHandler.ListBTFs)

	// Legacy of the beta release
	engine.POST("/generate", routesHandler.CustomizeBTFLegacy)
	engine.GET("/list", routesHandler.ListBTFsLegacy)

	monitoringRouterGroup := engine.Group("/monitoring")
	if !args.DisableMonitoring {
		monitoringRouterGroup.GET("/metrics", gin.WrapH(promhttp.Handler()))
	}
	healthHandler := healthcheck.NewHandler()
	monitoringRouterGroup.GET("/health", gin.WrapF(healthHandler.LiveEndpoint))
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

	// Create our middleware.
	registry := prometheus.NewRegistry()
	engine := setupEngine(registry)
	addRoutes(engine, handlers.NewRoutesHandler(archive, toolsDir))
	printAllRoutes(engine)

	if args.PrometheusPushGateway != "" {
		go pushPrometheusMetrics(args.PrometheusPushGateway, registry)
	}

	log.Printf("listening on 0.0.0.0:%s\n", args.Port)
	if err := engine.Run(fmt.Sprintf("0.0.0.0:%s", args.Port)); err != nil {
		log.Fatal(err)
	}
}
