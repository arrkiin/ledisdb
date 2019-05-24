package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	_ "net/http/pprof"
	"net/url"
	"os"
	"os/signal"
	"runtime"
	"strings"
	"syscall"

	"github.com/siddontang/ledisdb/config"
	"github.com/siddontang/ledisdb/server"
)

var configFile = flag.String("config", "", "ledisdb config file")
var addr = flag.String("addr", "", "ledisdb listen address")
var dataDir = flag.String("data_dir", "", "ledisdb base data dir")
var dbName = flag.String("db_name", "", "select a db to use, it will overwrite the config's db name")
var usePprof = flag.Bool("pprof", false, "enable pprof")
var pprofPort = flag.Int("pprof_port", 6060, "pprof http port")
var slaveof = flag.String("slaveof", "", "make the server a slave of another instance")
var promoAddr = flag.String("promo_addr", "", "address to promote to redis-failover service")
var failoverURL = flag.String("failover_url", "", "redis-failover service url like http://localhost/master")
var readonly = flag.Bool("readonly", false, "set readonly mode, slave server is always readonly")
var rpl = flag.Bool("rpl", false, "enable replication or not, slave server is always enabled")
var rplSync = flag.Bool("rpl_sync", false, "enable sync replication or not")
var ttlCheck = flag.Int("ttl_check", 0, "TTL check interval")
var databases = flag.Int("databases", 0, "ledisdb maximum database number")

func handleFailover(serviceURL, addr string) *string {
	// In case of failover handling we try forever to ge a proper master
	// or set ourself as master
	for {
		masterURL := ""
		res, e := http.PostForm(serviceURL, url.Values{
			"masters": {addr},
			"onempty": {"X"},
		})
		fmt.Printf("%+v - %+v", res, e)
		if e == nil {
			defer res.Body.Close()
			if res.StatusCode != http.StatusOK {
				continue
			}
			master, e := ioutil.ReadAll(res.Body)
			if e == nil {
				masterURL = string(master)
				return &masterURL
			}
		}
	}
}

func main() {
	runtime.GOMAXPROCS(runtime.NumCPU())

	flag.Parse()

	var cfg *config.Config
	var err error

	if len(*configFile) == 0 {
		println("no config set, using default config")
		cfg = config.NewConfigDefault()
	} else {
		cfg, err = config.NewConfigWithFile(*configFile)
	}

	if err != nil {
		println(err.Error())
		return
	}

	if len(*addr) > 0 {
		cfg.Addr = *addr
	}

	if len(*dataDir) > 0 {
		cfg.DataDir = *dataDir
	}

	if len(*dbName) > 0 {
		cfg.DBName = *dbName
	}

	if *databases > 0 {
		cfg.Databases = *databases
	}

	// check bool flag, use it.
	for _, arg := range os.Args {
		arg := strings.ToLower(arg)
		switch arg {
		case "-rpl", "-rpl=true", "-rpl=false":
			cfg.UseReplication = *rpl
		case "-readonly", "-readonly=true", "-readonly=false":
			cfg.Readonly = *readonly
		case "-rpl_sync", "-rpl_sync=true", "-rpl_sync=false":
			cfg.Replication.Sync = *rplSync
		}
	}

	if len(*failoverURL) > 0 && len(*promoAddr) > 0 {
		fmt.Printf("check for master via %s", *failoverURL)
		slaveof = handleFailover(*failoverURL, *promoAddr)
		if len(*slaveof) > 0 {
			fmt.Printf(" found %s\n", *slaveof)
		} else {
			fmt.Printf(" found nothing\n")
		}
	}

	if len(*slaveof) > 0 {
		cfg.SlaveOf = *slaveof
		cfg.Readonly = true
		cfg.UseReplication = true
	}

	if *ttlCheck > 0 {
		cfg.TTLCheckInterval = *ttlCheck
	}

	var app *server.App
	app, err = server.NewApp(cfg)
	if err != nil {
		println(err.Error())
		return
	}

	sc := make(chan os.Signal, 1)
	signal.Notify(sc,
		os.Kill,
		os.Interrupt,
		syscall.SIGHUP,
		syscall.SIGINT,
		syscall.SIGTERM,
		syscall.SIGQUIT)

	if *usePprof {
		go func() {
			log.Println(http.ListenAndServe(fmt.Sprintf(":%d", *pprofPort), nil))
		}()
	}

	go app.Run()

	<-sc

	println("ledis-server is closing")
	app.Close()
	println("ledis-server is closed")
}
