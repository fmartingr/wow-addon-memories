// Command memories-server serves the WoW Journey website and its upload API.
package main

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/httpserver"
)

const (
	exitOK    = 0
	exitError = 1
	exitUsage = 2
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	// After the first signal, restore the default handling so that a second one stops a slow shutdown at once.
	go func() {
		<-ctx.Done()
		stop()
	}()
	os.Exit(run(ctx, os.Args[1:], os.Getenv, os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, getenv func(string) string, stdout, stderr io.Writer) int {
	command := "serve"
	if len(args) > 0 {
		command = args[0]
	}
	if command != "serve" || len(args) > 1 {
		fmt.Fprintln(stderr, "usage: memories-server [serve]")
		return exitUsage
	}

	cfg, err := config.Load(getenv)
	if err != nil {
		fmt.Fprintf(stderr, "memories-server: the settings are not valid:\n%v\n", err)
		return exitUsage
	}

	log := slog.New(slog.NewJSONHandler(stdout, nil))
	if err := httpserver.Run(ctx, cfg, log); err != nil {
		fmt.Fprintf(stderr, "memories-server: %v\n", err)
		return exitError
	}
	return exitOK
}
