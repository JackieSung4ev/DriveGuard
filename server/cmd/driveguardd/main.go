package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"github.com/JackieSung4ev/gdrive/server/internal/api"
	"github.com/JackieSung4ev/gdrive/server/internal/auth"
	"github.com/JackieSung4ev/gdrive/server/internal/driveguard"
	"github.com/JackieSung4ev/gdrive/server/internal/jobs"
	"github.com/JackieSung4ev/gdrive/server/internal/plans"
)

func main() {
	addr := env("DRIVEGUARD_ADDR", "127.0.0.1:8080")
	client := driveguard.NewClient(env("DRIVEGUARD_SCRIPT", ""))
	jobManager := jobs.NewManager(client)
	planManager := plans.NewManager(nil)
	authStore, err := auth.NewStore(env("DRIVEGUARD_AUTH_FILE", defaultAuthFile()))
	if err != nil {
		log.Fatalf("auth store failed: %v", err)
	}

	httpServer := &http.Server{
		Addr:              addr,
		Handler:           api.NewServer(client, jobManager, planManager, authStore).Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Printf("driveguardd listening on http://%s", addr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server failed: %v", err)
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown failed: %v", err)
	}
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func defaultAuthFile() string {
	if runtime.GOOS == "windows" {
		return "driveguard-auth.json"
	}
	return "/etc/driveguard/web-auth.json"
}
