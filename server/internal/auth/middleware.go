package auth

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"

	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
	"github.com/fmartingr/wow-addon-memories/server/internal/ratelimit"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// Identity is the verified sender of a request.
type Identity struct {
	Public ed25519.PublicKey
	// Nonce of the request, kept so that a registration can store it together with the new key.
	Nonce []byte
	// Key is nil when the public key is not registered. Only Signed lets such a request through.
	Key *store.Key
}

type ctxKey struct{}

// FromContext returns the Identity that Signed or Registered put in the request context.
func FromContext(ctx context.Context) (Identity, bool) {
	id, ok := ctx.Value(ctxKey{}).(Identity)
	return id, ok
}

// Middleware verifies signed requests against the store.
type Middleware struct {
	Store *store.Store
	// PerKey limits the requests of one registered key.
	PerKey *ratelimit.Limiter
	Log    *slog.Logger
}

// Signed lets a request through when its signature is valid, its time is in the window and its nonce is new.
// The key may be unregistered; a registered key must not be revoked and is rate limited. The body is read up to
// maxBody bytes, because the signature covers it, and the handler reads it again from the request.
func (m *Middleware) Signed(maxBody int64, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// The cheap header and clock checks come first, so that an unsigned or stale request costs no body read.
		h, err := Parse(r)
		if err == nil {
			err = checkTime(h.Time, m.Store.Now())
		}
		if err != nil {
			failSignature(w, err)
			return
		}
		if r.Body == nil {
			r.Body = http.NoBody
		}
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBody))
		if err != nil {
			var tooBig *http.MaxBytesError
			if errors.As(err, &tooBig) {
				apierr.Write(w, http.StatusRequestEntityTooLarge, "too_large",
					fmt.Sprintf("The request is larger than the limit of %d bytes.", maxBody))
			} else {
				apierr.Write(w, http.StatusBadRequest, "bad_request", "The server could not read the request body. Try again.")
			}
			return
		}
		pub, err := verifyHeaders(r, h, body, m.Store.Now())
		if err != nil {
			failSignature(w, err)
			return
		}

		id := Identity{Public: pub, Nonce: h.Nonce}
		key, err := m.Store.KeyByPublic(r.Context(), pub)
		switch {
		case errors.Is(err, store.ErrNotFound):
		case err != nil:
			m.internal(w, "key lookup", err)
			return
		default:
			id.Key = &key
		}

		if id.Key != nil {
			if key.Revoked {
				apierr.KeyRevoked(w)
				return
			}
			// A replay is refused before the rate limit, so that a captured request cannot spend the quota of its key.
			seen, err := m.Store.NonceSeen(r.Context(), key.ID, h.Nonce)
			if err != nil {
				m.internal(w, "nonce", err)
				return
			}
			if seen {
				failSignature(w, ErrReplay)
				return
			}
			if ok, wait := m.PerKey.Allow(hex.EncodeToString(pub)); !ok {
				apierr.RateLimited(w, wait)
				return
			}
			fresh, err := m.Store.UseNonce(r.Context(), key.ID, h.Nonce)
			if err != nil {
				m.internal(w, "nonce", err)
				return
			}
			if !fresh {
				failSignature(w, ErrReplay)
				return
			}
		}

		r.Body = io.NopCloser(bytes.NewReader(body))
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, id)))
	})
}

// Registered is Signed for a key that is registered: an unknown key gets 401 not_registered. It also records that the key was seen.
func (m *Middleware) Registered(maxBody int64, next http.Handler) http.Handler {
	return m.Signed(maxBody, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, _ := FromContext(r.Context())
		if id.Key == nil {
			apierr.Write(w, http.StatusUnauthorized, "not_registered",
				"This key is not registered on this website. Register it first, with an invite code if the website asks for one.")
			return
		}
		if err := m.Store.TouchKey(r.Context(), id.Key.ID); err != nil {
			m.internal(w, "touch key", err)
			return
		}
		next.ServeHTTP(w, r)
	}))
}

func failSignature(w http.ResponseWriter, err error) {
	var e *Error
	msg := "The signature could not be checked."
	if errors.As(err, &e) {
		msg = e.Message
	}
	apierr.Write(w, http.StatusUnauthorized, "bad_signature", msg)
}

// internal logs the failure without any request data and answers 500.
func (m *Middleware) internal(w http.ResponseWriter, what string, err error) {
	apierr.Fail(w, m.Log, "auth failed", what, err)
}
