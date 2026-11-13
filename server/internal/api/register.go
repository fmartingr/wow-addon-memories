package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/ratelimit"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// registerLimit counts each registration attempt per client address, valid or not, before any work is done.
func (a *API) registerLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := ratelimit.ClientIP(r, a.cfg.TrustedProxies)
		if ok, wait := a.register.Allow(ratelimit.IPKey(ip)); !ok {
			apierr.RateLimited(w, wait)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *API) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Invite string `json:"invite"`
	}
	// Signed already read the whole body into memory, so decoding the request body reads no network bytes.
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil || dec.Decode(&struct{}{}) != io.EOF {
		badRequest(w, `The request body must be a JSON object such as {"invite": "CODE"} or {}. Update the app.`)
		return
	}

	id, _ := auth.FromContext(r.Context())
	created, err := a.store.Register(r.Context(), store.RegisterInput{
		Public:    id.Public,
		Nonce:     id.Nonce,
		Invite:    req.Invite,
		AllowOpen: a.gate.IsOpen(),
	})
	switch {
	case errors.Is(err, store.ErrInviteInvalid):
		apierr.Write(w, http.StatusForbidden, "invite_invalid",
			"This invite code is not valid. It may be wrong, already used, expired or revoked. Ask the website admin for a new code.")
	case errors.Is(err, store.ErrKeyRevoked):
		apierr.KeyRevoked(w)
	case err != nil:
		a.internal(w, "register", err)
	case created:
		apierr.JSON(w, http.StatusCreated, map[string]bool{"registered": true})
	default:
		apierr.JSON(w, http.StatusOK, map[string]bool{"registered": true})
	}
}
