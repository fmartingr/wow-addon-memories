package httpserver

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
)

func signedRequest(method, target, body string, priv ed25519.PrivateKey) *http.Request {
	now := time.Now().Unix()
	nonce := base64.RawURLEncoding.EncodeToString([]byte("0123456789abcdef"))
	enc := base64.RawURLEncoding.EncodeToString
	req := httptest.NewRequest(method, target, strings.NewReader(body))
	req.Header.Set(auth.HeaderKey, enc(priv.Public().(ed25519.PublicKey)))
	req.Header.Set(auth.HeaderTime, strconv.FormatInt(now, 10))
	req.Header.Set(auth.HeaderNonce, nonce)
	req.Header.Set(auth.HeaderSignature, enc(ed25519.Sign(priv, []byte(auth.SignedString(method, target, now, nonce, []byte(body))))))
	return req
}

func TestSignedAPIIsWiredIntoThePublicHandler(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, map[string]string{"MEMORIES_REGISTRATION": "open"}), io.Discard)
	_, priv, _ := ed25519.GenerateKey(nil)

	rec := httptest.NewRecorder()
	public.ServeHTTP(rec, signedRequest("POST", "/api/v1/register", "{}", priv))
	if rec.Code != http.StatusCreated {
		t.Fatalf("register: %d %s", rec.Code, rec.Body)
	}
	checkSecurityHeaders(t, rec, "register")

	rec = httptest.NewRecorder()
	req := signedRequestWithNonce(signedRequest("GET", "/api/v1/me", "", priv), priv, "AAAAAAAAAAAAAAAAAAAAAA")
	public.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"screenshots":"none"`) {
		t.Errorf("me: %d %s", rec.Code, rec.Body)
	}

	rec = do(public, http.MethodGet, "/api/v1/me")
	if rec.Code != http.StatusUnauthorized || !strings.Contains(rec.Body.String(), "bad_signature") {
		t.Errorf("unsigned me: %d %s", rec.Code, rec.Body)
	}
}

func signedRequestWithNonce(req *http.Request, priv ed25519.PrivateKey, nonce string) *http.Request {
	t, _ := strconv.ParseInt(req.Header.Get(auth.HeaderTime), 10, 64)
	msg := auth.SignedString(req.Method, req.RequestURI, t, nonce, nil)
	req.Header.Set(auth.HeaderNonce, nonce)
	req.Header.Set(auth.HeaderSignature, base64.RawURLEncoding.EncodeToString(ed25519.Sign(priv, []byte(msg))))
	return req
}

func TestPageRateLimitFollowsTheClientAddress(t *testing.T) {
	vars := map[string]string{"MEMORIES_RATE_PUBLIC_PER_MINUTE": "2", "MEMORIES_TRUSTED_PROXIES": "10.0.0.0/8"}
	public, _ := newHandlers(t, loadConfig(t, vars), io.Discard)
	get := func(path, remote, xff string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("GET", path, nil)
		req.RemoteAddr = remote
		if xff != "" {
			req.Header.Set("X-Forwarded-For", xff)
		}
		rec := httptest.NewRecorder()
		public.ServeHTTP(rec, req)
		return rec
	}
	for range 2 {
		if rec := get("/", "192.0.2.1:1", ""); rec.Code != http.StatusOK {
			t.Fatalf("status %d", rec.Code)
		}
	}
	rec := get("/robots.txt", "192.0.2.1:1", "")
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") == "" {
		t.Errorf("status %d, Retry-After %q; want 429 with a wait", rec.Code, rec.Header().Get("Retry-After"))
	}
	checkSecurityHeaders(t, rec, "429")
	if rec := get("/nothing", "192.0.2.1:1", ""); rec.Code != http.StatusTooManyRequests {
		t.Errorf("the 404 page is not limited: %d", rec.Code)
	}
	if rec := get("/api/v1/info", "192.0.2.1:1", ""); rec.Code != http.StatusTooManyRequests || !strings.Contains(rec.Body.String(), `"rate_limited"`) {
		t.Errorf("the API is not limited per address: %d %s", rec.Code, rec.Body)
	}
	if rec := get("/", "192.0.2.2:1", ""); rec.Code != http.StatusOK {
		t.Errorf("another address: %d", rec.Code)
	}
	if rec := get("/", "192.0.2.1:1", "203.0.113.7"); rec.Code != http.StatusTooManyRequests {
		t.Errorf("a forged header from an untrusted peer gave a new limit: %d", rec.Code)
	}
	for _, client := range []string{"203.0.113.1", "203.0.113.2"} {
		if rec := get("/", "10.1.1.1:1", client); rec.Code != http.StatusOK {
			t.Errorf("client %s behind the proxy: %d", client, rec.Code)
		}
	}
}

func TestRunCreatesTheDatabaseInTheDataFolder(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "nested", "data")
	cfg := loadConfig(t, map[string]string{
		"MEMORIES_DATA_DIR":    dir,
		"MEMORIES_PUBLIC_ADDR": freeAddr(t),
		"MEMORIES_ADMIN_ADDR":  freeAddr(t),
	})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg, quietLog()) }()
	for range 100 {
		if _, err := os.Stat(filepath.Join(dir, "memories.db")); err == nil {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "memories.db")); err != nil {
		t.Errorf("no database in the data folder: %v", err)
	}
}

func TestRunReportsAnUnusableDataFolder(t *testing.T) {
	file := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(file, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := loadConfig(t, map[string]string{
		"MEMORIES_DATA_DIR":    file,
		"MEMORIES_PUBLIC_ADDR": freeAddr(t),
		"MEMORIES_ADMIN_ADDR":  freeAddr(t),
	})
	err := Run(context.Background(), cfg, quietLog())
	if err == nil || !strings.Contains(err.Error(), file) || !strings.Contains(err.Error(), "writable") {
		t.Errorf("Run = %v, want an error that names the folder", err)
	}
}

func TestRunReportsADamagedDatabase(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "memories.db"), []byte(strings.Repeat("junk ", 500)), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := loadConfig(t, map[string]string{"MEMORIES_DATA_DIR": dir, "MEMORIES_PUBLIC_ADDR": freeAddr(t), "MEMORIES_ADMIN_ADDR": freeAddr(t)})
	if err := Run(context.Background(), cfg, quietLog()); err == nil || !strings.Contains(err.Error(), "memories.db") {
		t.Errorf("Run = %v, want an error that names the database", err)
	}
}
