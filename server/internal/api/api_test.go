package api

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/characters"
	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

type fakeClock struct{ t time.Time }

func (c *fakeClock) Now() time.Time          { return c.t }
func (c *fakeClock) Advance(d time.Duration) { c.t = c.t.Add(d) }

type env struct {
	t     *testing.T
	cfg   config.Config
	st    *store.Store
	clock *fakeClock
	h     http.Handler
	logs  *bytes.Buffer
	db    string
	data  string
	api   *API
	wrap  func(store.Blobs) store.Blobs
	chars *characters.Service
}

func newEnv(t *testing.T, vars map[string]string) *env {
	t.Helper()
	e := &env{t: t, logs: &bytes.Buffer{}, data: t.TempDir(), clock: &fakeClock{t: time.Unix(1794000000, 0)}}
	cfg, err := config.Load(func(k string) string { return vars[k] })
	if err != nil {
		t.Fatal(err)
	}
	e.cfg = cfg
	e.db = filepath.Join(e.data, "memories.db")
	e.start()
	return e
}

// start opens the store and builds the handler; a second call plays a restart of the server.
func (e *env) start() {
	e.t.Helper()
	st, err := store.Open(e.db)
	if err != nil {
		e.t.Fatal(err)
	}
	st.SetClock(e.clock.Now)
	e.t.Cleanup(func() { st.Close() })
	e.st = st
	blobs, err := store.NewDiskBlobs(e.data)
	if err != nil {
		e.t.Fatal(err)
	}
	var b store.Blobs = blobs
	if e.wrap != nil {
		b = e.wrap(blobs)
	}
	log := slog.New(slog.NewJSONHandler(e.logs, nil))
	e.chars = characters.New(st, b, log)
	mux := http.NewServeMux()
	e.api = New(e.cfg, st, e.chars, log)
	e.api.Routes(mux)
	e.h = mux
}

type client struct {
	priv ed25519.PrivateKey
	seq  uint64
	ip   string
	xff  string
}

func newClient(n byte) *client {
	return &client{priv: ed25519.NewKeyFromSeed(bytes.Repeat([]byte{n}, 32)), ip: "192.0.2." + strconv.Itoa(int(n))}
}

func (c *client) public() ed25519.PublicKey { return c.priv.Public().(ed25519.PublicKey) }

func (c *client) nextNonce() []byte {
	c.seq++
	n := make([]byte, 16)
	copy(n, c.public()[:8])
	binary.BigEndian.PutUint64(n[8:], c.seq)
	return n
}

type signOpts struct {
	nonce []byte
	time  int64
}

// request builds a signed request. It returns the request so that a test can send it twice.
func (e *env) request(c *client, method, target, body string, o ...signOpts) *http.Request {
	var opt signOpts
	if len(o) > 0 {
		opt = o[0]
	}
	if opt.nonce == nil {
		opt.nonce = c.nextNonce()
	}
	if opt.time == 0 {
		opt.time = e.clock.Now().Unix()
	}
	nonce := base64Raw(opt.nonce)
	msg := auth.SignedString(method, target, opt.time, nonce, []byte(body))
	req := httptest.NewRequest(method, target, strings.NewReader(body))
	req.RemoteAddr = c.ip + ":4000"
	if c.xff != "" {
		req.Header.Set("X-Forwarded-For", c.xff)
	}
	req.Header.Set(auth.HeaderKey, base64Raw(c.public()))
	req.Header.Set(auth.HeaderTime, strconv.FormatInt(opt.time, 10))
	req.Header.Set(auth.HeaderNonce, nonce)
	req.Header.Set(auth.HeaderSignature, base64Raw(ed25519.Sign(c.priv, []byte(msg))))
	return req
}

func (e *env) serve(req *http.Request) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	return rec
}

func (e *env) do(c *client, method, target, body string) *httptest.ResponseRecorder {
	return e.serve(e.request(c, method, target, body))
}

func (e *env) register(c *client, invite string) *httptest.ResponseRecorder {
	return e.do(c, "POST", "/api/v1/register", `{"invite":"`+invite+`"}`)
}

func (e *env) invite() string {
	e.t.Helper()
	_, code, err := e.st.CreateInvite(bg, "test", 30*24*time.Hour)
	if err != nil {
		e.t.Fatal(err)
	}
	return code
}

func (e *env) registered(c *client) {
	e.t.Helper()
	if rec := e.register(c, e.invite()); rec.Code != http.StatusCreated {
		e.t.Fatalf("registration: %d %s", rec.Code, rec.Body)
	}
}

func (e *env) revoke(c *client) {
	e.t.Helper()
	k, err := e.st.KeyByPublic(bg, c.public())
	if err != nil {
		e.t.Fatal(err)
	}
	if err := e.st.RevokeKey(bg, k.ID); err != nil {
		e.t.Fatal(err)
	}
}

type answer struct {
	Error       string `json:"error"`
	Message     string `json:"message"`
	Registered  bool   `json:"registered"`
	Screenshots string `json:"screenshots"`
	Characters  []struct {
		Path    string `json:"path"`
		URL     string `json:"url"`
		GUID    string `json:"guid"`
		Steps   int64  `json:"steps"`
		Updated int64  `json:"updated"`
	} `json:"characters"`
}

func decode(t *testing.T, rec *httptest.ResponseRecorder) answer {
	t.Helper()
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type = %q", ct)
	}
	var a answer
	if err := json.Unmarshal(rec.Body.Bytes(), &a); err != nil {
		t.Fatalf("body %q is not JSON: %v", rec.Body, err)
	}
	return a
}

func expectError(t *testing.T, rec *httptest.ResponseRecorder, status int, code string) answer {
	t.Helper()
	a := decode(t, rec)
	if rec.Code != status || a.Error != code {
		t.Fatalf("status %d error %q (%s); want %d %q", rec.Code, a.Error, a.Message, status, code)
	}
	if a.Message == "" || strings.Contains(a.Message, "goroutine") {
		t.Errorf("message = %q, want plain English", a.Message)
	}
	return a
}

var bg = context.Background()

func base64Raw(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// registered2 registers the key in open mode.
func (e *env) registered2(c *client) {
	e.t.Helper()
	if rec := e.do(c, "POST", "/api/v1/register", "{}"); rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		e.t.Fatalf("registration: %d %s", rec.Code, rec.Body)
	}
}

func nonceOf(t *testing.T, req *http.Request) []byte {
	t.Helper()
	n, err := base64.RawURLEncoding.DecodeString(req.Header.Get(auth.HeaderNonce))
	if err != nil {
		t.Fatal(err)
	}
	return n
}

func claimOf(realm, name string, keyID, steps int64) store.Claim {
	guid := "Player-1-0000000" + strings.ToUpper(strconv.FormatInt(steps, 16))
	return store.Claim{Flavor: "wow", Region: "eu", Realm: realm, Name: name, GUID: guid, KeyID: keyID, Steps: steps}
}
