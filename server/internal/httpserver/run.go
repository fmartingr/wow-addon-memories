package httpserver

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/site"
)

const shutdownTimeout = 10 * time.Second

// newServer routes the errors of net/http itself (a handler panic, an accept error) to log, so that every log line is JSON.
func newServer(addr string, h http.Handler, log *slog.Logger) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelError),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
}

func siteOptions(cfg config.Config) site.Options {
	return site.Options{
		Name:             cfg.SiteName,
		GitHubURL:        cfg.GitHubURL,
		OpenRegistration: cfg.Registration == config.RegistrationOpen,
	}
}

// Run serves the public and admin listeners until ctx ends or a listener fails, then shuts both down.
// It returns nil after a clean shutdown.
func Run(ctx context.Context, cfg config.Config, log *slog.Logger) error {
	pages, err := site.New(siteOptions(cfg))
	if err != nil {
		return err
	}
	public := newServer(cfg.PublicAddr, NewPublic(cfg, pages, log), log)
	admin := newServer(cfg.AdminAddr, NewAdmin(pages, log), log)

	// Listen first, so that a busy port is reported before any request is served.
	var listeners []net.Listener
	closeAll := func() {
		for _, l := range listeners {
			l.Close()
		}
	}
	servers := []*http.Server{public, admin}
	for _, srv := range servers {
		l, err := net.Listen("tcp", srv.Addr)
		if err != nil {
			closeAll()
			return fmt.Errorf("%w. Check the address, and that no other program uses that port.", err)
		}
		listeners = append(listeners, l)
	}

	failed := make(chan error, len(servers))
	for i, srv := range servers {
		log.Info("listening", "addr", listeners[i].Addr().String())
		go func() { failed <- srv.Serve(listeners[i]) }()
	}

	var runErr error
	select {
	case <-ctx.Done():
	case runErr = <-failed:
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	shutdownErrs := make([]error, len(servers))
	var wg sync.WaitGroup
	for i, srv := range servers {
		wg.Go(func() {
			if err := srv.Shutdown(shutdownCtx); err != nil {
				srv.Close()
				shutdownErrs[i] = err
			}
		})
	}
	wg.Wait()
	if runErr == nil {
		runErr = errors.Join(shutdownErrs...)
	}
	return runErr
}
