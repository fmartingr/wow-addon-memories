// Package api implements the signed JSON API under /api/v1.
package api

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/characters"
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
	chars    *characters.Service
	auth     *auth.Middleware
	register *ratelimit.Limiter

	// slots holds one token for each upload that is being decoded and stored. A decoded upload of the largest size takes
	// about 800 MB, and a save also decodes the stored character (see maxCharacterBytes), so the server runs only
	// MaxConcurrentUploads of them at a time.
	slots      chan struct{}
	uploadWait time.Duration
}

// defaultUploadWait is how long an upload waits for a free slot before the server answers 503.
const defaultUploadWait = 10 * time.Second

// New builds the API from the config. The rate limits come from the config.
func New(cfg config.Config, st *store.Store, chars *characters.Service, log *slog.Logger) *API {
	return &API{
		cfg:   cfg,
		store: st,
		log:   log,
		auth: &auth.Middleware{
			Store:  st,
			PerKey: ratelimit.New(cfg.RateSignedPerMinute, time.Minute),
			Log:    log,
		},
		register:   ratelimit.New(cfg.RateRegisterPerHour, time.Hour),
		chars:      chars,
		slots:      make(chan struct{}, cfg.MaxConcurrentUploads),
		uploadWait: defaultUploadWait,
	}
}

// Routes adds the routes of the API to mux.
func (a *API) Routes(mux *http.ServeMux) {
	mux.Handle("POST /api/v1/register", a.registerLimit(a.auth.Signed(smallBody, http.HandlerFunc(a.handleRegister))))
	mux.Handle("GET /api/v1/me", a.auth.Registered(smallBody, http.HandlerFunc(a.handleMe)))
	mux.Handle("POST /api/v1/characters", a.auth.Registered(a.cfg.MaxUploadBytes, http.HandlerFunc(a.handleUpload)))
	mux.Handle("DELETE /api/v1/characters/{flavor}/{region}/{realm}/{name}", a.auth.Registered(smallBody, http.HandlerFunc(a.handleDelete)))
	mux.Handle("POST /api/v1/screenshots/request", a.auth.Registered(smallBody, http.HandlerFunc(a.handleScreenshotsRequest)))
}
