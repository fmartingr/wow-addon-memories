// Package httpserver builds the public and admin handlers and runs their listeners.
package httpserver

import (
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/api"
	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
	"github.com/fmartingr/wow-addon-memories/server/internal/characters"
	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/ratelimit"
	"github.com/fmartingr/wow-addon-memories/server/internal/site"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// NewPublic returns the handler of the public listener.
func NewPublic(cfg config.Config, s *site.Site, pages *site.Pages, st *store.Store, chars *characters.Service, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /{$}", s.Home())
	mux.Handle("GET /robots.txt", s.Robots())
	mux.Handle("GET "+site.CSSPath, s.CSS())
	mux.HandleFunc("GET /api/v1/info", func(w http.ResponseWriter, r *http.Request) {
		apierr.JSON(w, http.StatusOK, map[string]any{
			"api":          1,
			"name":         cfg.SiteName,
			"registration": cfg.Registration,
		})
	})
	api.New(cfg, st, chars, log).Routes(mux)
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		apierr.Write(w, http.StatusNotFound, "not_found", "There is no such API path. Check the address of the request.")
	})
	pages.Routes(mux)
	// The per-IP limit covers the API too, so that signed requests of unregistered keys and the unsigned API paths
	// cannot flood the server; the API adds its own tighter limits per key and per registration.
	limited := ratelimit.PerIP(ratelimit.New(cfg.RatePublicPerMinute, time.Minute), cfg.TrustedProxies,
		site.LangChoice(strings.HasPrefix(cfg.SiteURL, "https://"), mux))
	// The viewer files are outside the limit: one visit of a map loads 100 to 300 tiles. Only fixed files and the two
	// art folders are served there, with no directory listing.
	outer := http.NewServeMux()
	outer.Handle(site.AssetPrefix, pages.Assets())
	outer.Handle("/", limited)
	return site.Headers(logRequests(log, outer))
}

// NewAdmin returns the handler of the admin listener: the admin pages behind the security headers and the request log.
func NewAdmin(pages http.Handler, log *slog.Logger) http.Handler {
	return site.Headers(logRequests(log, pages))
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

// Unwrap lets http.ResponseController reach the connection (deadlines, Flush) through the logging wrapper.
func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// logRequests logs the method, the path and the outcome. It never logs a header, a query or a body, because the
// Memories-* headers and the bodies carry secrets and player data.
func logRequests(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		// A map visit makes hundreds of tile requests, so the viewer files are logged only when they fail.
		if strings.HasPrefix(r.URL.Path, site.AssetPrefix) && sw.status < http.StatusBadRequest {
			return
		}
		log.Info("request", "method", r.Method, "path", r.URL.Path, "status", sw.status,
			"ms", time.Since(start).Milliseconds())
	})
}
