// Package httpserver builds the public and admin handlers and runs their listeners.
package httpserver

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/site"
)

// NewPublic returns the handler of the public listener.
func NewPublic(cfg config.Config, s *site.Site, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /{$}", s.Home())
	mux.Handle("GET /robots.txt", s.Robots())
	mux.Handle("GET "+site.CSSPath, s.CSS())
	mux.HandleFunc("GET /api/v1/info", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"api":          1,
			"name":         cfg.SiteName,
			"registration": cfg.Registration,
		})
	})
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error":   "not_found",
			"message": "There is no such API path. Check the address of the request.",
		})
	})
	mux.Handle("/", s.NotFound())
	return site.Headers(logRequests(log, mux))
}

// NewAdmin returns the handler of the admin listener. It answers 404 to every request until the admin page exists.
func NewAdmin(s *site.Site, log *slog.Logger) http.Handler {
	return site.Headers(logRequests(log, s.NotFound()))
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		http.Error(w, "The server could not build the answer.", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write(append(body, '\n'))
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
		log.Info("request", "method", r.Method, "path", r.URL.Path, "status", sw.status,
			"ms", time.Since(start).Milliseconds())
	})
}
