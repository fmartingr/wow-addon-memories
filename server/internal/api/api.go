// Package api implements the signed JSON API under /api/v1.
package api

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/ratelimit"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// smallBody is the body limit of the routes that take no upload: 1 KiB.
const smallBody = 1 << 10

// API holds what the handlers share.
type API struct {
	cfg      config.Config
	store    *store.Store
	log      *slog.Logger
	auth     *auth.Middleware
	register *ratelimit.Limiter
}

// New builds the API from the config. The rate limits come from the config.
func New(cfg config.Config, st *store.Store, log *slog.Logger) *API {
	return &API{
		cfg:   cfg,
		store: st,
		log:   log,
		auth: &auth.Middleware{
			Store:  st,
			PerKey: ratelimit.New(cfg.RateSignedPerMinute, time.Minute),
			Log:    log,
		},
		register: ratelimit.New(cfg.RateRegisterPerHour, time.Hour),
	}
}

// Routes adds the routes of the API to mux.
func (a *API) Routes(mux *http.ServeMux) {
	mux.Handle("POST /api/v1/register", a.registerLimit(a.auth.Signed(smallBody, http.HandlerFunc(a.handleRegister))))
	mux.Handle("GET /api/v1/me", a.auth.Registered(smallBody, http.HandlerFunc(a.handleMe)))
	mux.Handle("POST /api/v1/screenshots/request", a.auth.Registered(smallBody, http.HandlerFunc(a.handleScreenshotsRequest)))
}
