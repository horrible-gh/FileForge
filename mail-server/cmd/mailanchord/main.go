// Command mailanchord is the MailAnchor Go backend (Phase 0 base).
// It owns the P0007 /auth/* contract and the DB0008 schema; mail/management/sync
// endpoints are added in Phase 1 (NR0003 §6).
package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/config"
	"mailanchor/serverd/internal/db"
	"mailanchor/serverd/internal/server"
)

func main() {
	seedEmail := flag.String("seed-email", "", "dev: create a user with this email then exit")
	seedPass := flag.String("seed-password", "", "dev: password for -seed-email")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	driver, err := db.NormalizeDriver(cfg.DBType)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	database, err := db.OpenDB(db.Config{
		Driver:   driver,
		Path:     cfg.DBPath,
		Host:     cfg.DBHost,
		Port:     cfg.DBPort,
		User:     cfg.DBUser,
		Password: cfg.DBPassword,
		Database: cfg.DBName,
	})
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer database.Close()

	// Dev seeding (signup is DEFERRED per L0011); useful for manual smoke runs.
	if *seedEmail != "" {
		u, serr := auth.NewStore(database).CreateUser(*seedEmail, *seedPass, "")
		if serr != nil {
			log.Fatalf("seed: %v", serr)
		}
		log.Printf("seeded user %s (%s)", u.ID, u.Email)
		return
	}

	srv := &http.Server{
		Handler:           server.New(cfg, database),
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Bind the listen address synchronously BEFORE announcing "listening", so a
	// port conflict (a previous mailanchord instance still holding cfg.Addr) fails
	// here with an actionable message instead of printing a misleading "listening"
	// line and then dying with a raw socket error. This is the only boot failure a
	// user editing GOOGLE_* would actually hit: the credential values themselves do
	// not affect startup — an unconfigured provider only makes the OAuth endpoints
	// answer 503 (NR0003), it never blocks boot.
	ln, err := net.Listen("tcp", cfg.Addr)
	if err != nil {
		log.Fatalf("listen %s: %v\n"+
			"    The address %s is already in use — most likely a previous mailanchord\n"+
			"    instance is still running. Stop it (Windows: taskkill /F /IM mailanchord.exe),\n"+
			"    confirm nothing is listening on %s, then start again. (Gmail OAuth\n"+
			"    GOOGLE_CLIENT_ID/SECRET/REDIRECT_URI do NOT affect whether the server boots.)",
			cfg.Addr, err, cfg.Addr, cfg.Addr)
	}

	go func() {
		log.Printf("mailanchord listening on %s (context %s, db %s)", cfg.Addr, cfg.Context, driver)
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("serve: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	log.Println("stopped")
}
