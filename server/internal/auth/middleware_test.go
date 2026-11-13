package auth

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/ratelimit"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

var bg = context.Background()

type fixture struct {
	t    *testing.T
	st   *store.Store
	mw   *Middleware
	logs *bytes.Buffer
	now  time.Time
}

func newFixture(t *testing.T, perKey int64) *fixture {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	f := &fixture{t: t, st: st, logs: &bytes.Buffer{}, now: time.Unix(1794000000, 0)}
	st.SetClock(func() time.Time { return f.now })
	f.mw = &Middleware{Store: st, PerKey: ratelimit.New(perKey, time.Minute), Log: slog.New(slog.NewJSONHandler(f.logs, nil))}
	return f
}

func (f *fixture) register(priv ed25519.PrivateKey) store.Key {
	f.t.Helper()
	pub := priv.Public().(ed25519.PublicKey)
	if _, err := f.st.Register(bg, store.RegisterInput{Public: pub, Nonce: make([]byte, 16), AllowOpen: true}); err != nil {
		f.t.Fatal(err)
	}
	k, err := f.st.KeyByPublic(bg, pub)
	if err != nil {
		f.t.Fatal(err)
	}
	return k
}

type seen struct {
	id   Identity
	body string
	hit  bool
}

func (s *seen) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.hit = true
		s.id, _ = FromContext(r.Context())
		b, _ := io.ReadAll(r.Body)
		s.body = string(b)
		w.WriteHeader(http.StatusNoContent)
	})
}

func (f *fixture) send(h http.Handler, o reqOpts) *httptest.ResponseRecorder {
	if o.time == 0 {
		o.time = f.now.Unix()
	}
	req := signed(o)
	req.Body = io.NopCloser(bytes.NewReader(o.body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func errCode(t *testing.T, rec *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	var got struct{ Error, Message string }
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("body %q: %v", rec.Body, err)
	}
	if rec.Code != status || got.Error != code || got.Message == "" {
		t.Fatalf("status %d, %+v; want %d %s with a message", rec.Code, got, status, code)
	}
}

func key(n byte) ed25519.PrivateKey { return ed25519.NewKeyFromSeed(bytes.Repeat([]byte{n}, 32)) }

func TestSignedPassesTheIdentityAndTheBody(t *testing.T) {
	f := newFixture(t, 100)
	var s seen
	h := f.mw.Signed(1<<10, s.handler())

	t.Run("an unregistered key", func(t *testing.T) {
		priv := key(1)
		rec := f.send(h, reqOpts{priv: priv, body: []byte(`{"a":1}`), nonce: bytes.Repeat([]byte{1}, 16)})
		if rec.Code != http.StatusNoContent {
			t.Fatalf("status %d: %s", rec.Code, rec.Body)
		}
		if s.id.Key != nil || !bytes.Equal(s.id.Public, priv.Public().(ed25519.PublicKey)) || !bytes.Equal(s.id.Nonce, bytes.Repeat([]byte{1}, 16)) {
			t.Errorf("identity = %+v", s.id)
		}
		if s.body != `{"a":1}` {
			t.Errorf("the handler read %q, want the signed body", s.body)
		}
		// The request is not stored until the handler registers the key, so the same request passes again here.
		if rec := f.send(h, reqOpts{priv: priv, body: []byte(`{"a":1}`), nonce: bytes.Repeat([]byte{1}, 16)}); rec.Code != http.StatusNoContent {
			t.Errorf("repeat of an unregistered request: %d", rec.Code)
		}
	})

	t.Run("a registered key, once per nonce", func(t *testing.T) {
		priv := key(2)
		k := f.register(priv)
		s = seen{}
		if rec := f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{2}, 16)}); rec.Code != http.StatusNoContent {
			t.Fatalf("status %d", rec.Code)
		}
		if s.id.Key == nil || s.id.Key.ID != k.ID {
			t.Errorf("identity key = %+v", s.id.Key)
		}
		s = seen{}
		errCode(t, f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{2}, 16)}), 401, "bad_signature")
		if s.hit {
			t.Error("the handler ran for a replay")
		}
	})
}

func TestSignedRejections(t *testing.T) {
	f := newFixture(t, 100)
	var s seen
	h := f.mw.Signed(16, s.handler())

	t.Run("no headers", func(t *testing.T) {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/register", strings.NewReader("{}")))
		errCode(t, rec, 401, "bad_signature")
	})
	t.Run("the body is larger than the limit", func(t *testing.T) {
		errCode(t, f.send(h, reqOpts{body: bytes.Repeat([]byte("x"), 17)}), 413, "too_large")
	})
	t.Run("the body is not the signed body", func(t *testing.T) {
		req := signed(reqOpts{time: f.now.Unix(), body: []byte("signed")})
		req.Body = io.NopCloser(strings.NewReader("forged"))
		rec := httptest.NewRecorder()
		s = seen{}
		h.ServeHTTP(rec, req)
		errCode(t, rec, 401, "bad_signature")
		if s.hit {
			t.Error("the handler ran for a forged body")
		}
	})
	t.Run("a stale request is refused before its body is read", func(t *testing.T) {
		rec := f.send(h, reqOpts{time: f.now.Unix() - MaxSkew - 1, body: bytes.Repeat([]byte("x"), 17)})
		errCode(t, rec, 401, "bad_signature")
		if !strings.Contains(rec.Body.String(), "clock") {
			t.Errorf("body %s does not point at the clock", rec.Body.String())
		}
	})
	t.Run("the body is exactly the limit", func(t *testing.T) {
		if rec := f.send(h, reqOpts{body: bytes.Repeat([]byte("x"), 16)}); rec.Code != http.StatusNoContent {
			t.Errorf("status %d", rec.Code)
		}
	})
	t.Run("the body cannot be read", func(t *testing.T) {
		req := signed(reqOpts{time: f.now.Unix()})
		req.Body = io.NopCloser(errReader{})
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		errCode(t, rec, 400, "bad_request")
	})
	t.Run("a nil body counts as empty", func(t *testing.T) {
		req := signed(reqOpts{method: "GET", target: "/api/v1/me", time: f.now.Unix()})
		req.Body = nil
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusNoContent {
			t.Errorf("status %d", rec.Code)
		}
	})
	t.Run("the clock is off", func(t *testing.T) {
		rec := f.send(h, reqOpts{time: f.now.Unix() - 301})
		errCode(t, rec, 401, "bad_signature")
		if !strings.Contains(rec.Body.String(), "clock") {
			t.Errorf("body %s does not mention the clock", rec.Body)
		}
	})
}

// A request is valid for MaxSkew on each side of the server time, so the server must remember a nonce for twice that.
func TestNonceMemoryCoversTheTimeWindow(t *testing.T) {
	if store.NonceTTL < 2*MaxSkew*time.Second {
		t.Errorf("store.NonceTTL = %v, want at least %v", store.NonceTTL, 2*MaxSkew*time.Second)
	}
}

type errReader struct{}

func (errReader) Read([]byte) (int, error) { return 0, errors.New("connection reset") }

func TestSignedRevokedAndRateLimited(t *testing.T) {
	f := newFixture(t, 2)
	var s seen
	h := f.mw.Signed(1<<10, s.handler())

	priv := key(3)
	k := f.register(priv)
	for i := range 2 {
		if rec := f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{byte(i + 1)}, 16)}); rec.Code != http.StatusNoContent {
			t.Fatalf("request %d: %d", i+1, rec.Code)
		}
	}
	rec := f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{9}, 16)})
	errCode(t, rec, 429, "rate_limited")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("no Retry-After")
	}
	// A limited request must not burn its nonce: the client can send it again later.
	f.mw.PerKey = ratelimit.New(100, time.Minute)
	if rec := f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{9}, 16)}); rec.Code != http.StatusNoContent {
		t.Errorf("the nonce of a limited request was spent: %d", rec.Code)
	}

	// A replay is refused without spending the quota of the key.
	f.mw.PerKey = ratelimit.New(1, time.Minute)
	for range 3 {
		errCode(t, f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{9}, 16)}), 401, "bad_signature")
	}
	if rec := f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{11}, 16)}); rec.Code != http.StatusNoContent {
		t.Errorf("replays spent the rate limit: %d", rec.Code)
	}

	if err := f.st.RevokeKey(bg, k.ID); err != nil {
		t.Fatal(err)
	}
	s = seen{}
	errCode(t, f.send(h, reqOpts{priv: priv, nonce: bytes.Repeat([]byte{10}, 16)}), 403, "key_revoked")
	if s.hit {
		t.Error("the handler ran for a revoked key")
	}
}

func TestRegisteredRequiresAKey(t *testing.T) {
	f := newFixture(t, 100)
	var s seen
	h := f.mw.Registered(1<<10, s.handler())

	errCode(t, f.send(h, reqOpts{priv: key(4)}), 401, "not_registered")
	if s.hit {
		t.Fatal("the handler ran for an unregistered key")
	}

	priv := key(5)
	k := f.register(priv)
	f.now = f.now.Add(time.Minute)
	if rec := f.send(h, reqOpts{priv: priv}); rec.Code != http.StatusNoContent {
		t.Fatalf("status %d", rec.Code)
	}
	if after, _ := f.st.KeyByPublic(bg, priv.Public().(ed25519.PublicKey)); after.LastSeen != f.now.Unix() || after.ID != k.ID {
		t.Errorf("LastSeen = %d, want %d", after.LastSeen, f.now.Unix())
	}
}

func TestStoreFailureGives500AndLogsNoSecret(t *testing.T) {
	f := newFixture(t, 100)
	priv := key(6)
	f.register(priv)
	f.st.Close()
	rec := f.send(f.mw.Signed(1<<10, (&seen{}).handler()), reqOpts{priv: priv})
	errCode(t, rec, 500, "internal")
	logs := f.logs.String()
	if !strings.Contains(logs, "auth failed") {
		t.Errorf("logs = %q", logs)
	}
	for _, secret := range []string{b64.EncodeToString(priv.Public().(ed25519.PublicKey)), "Memories"} {
		if strings.Contains(logs, secret) {
			t.Errorf("the log holds %q", secret)
		}
	}
}

func TestFailSignatureWithAForeignError(t *testing.T) {
	rec := httptest.NewRecorder()
	failSignature(rec, errors.New("odd"))
	errCode(t, rec, 401, "bad_signature")
	if _, ok := FromContext(context.Background()); ok {
		t.Error("FromContext found an identity in an empty context")
	}
}
