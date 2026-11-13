package admin

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/api"
	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/characters"
	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/openreg"
	"github.com/fmartingr/wow-addon-memories/server/internal/site"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

const (
	expectedDir = "../../../testdata/expected"
	imagesDir   = "../images/testdata"
	adminHost   = "127.0.0.1:8081"
	brumamar    = "wow/eu/brumamar/nandu"
	errantes    = "wow/eu/los-errantes/nandu"
	shotA       = "WoWScrnShot_110126_114820.jpg"
	shotB       = "WoWScrnShot_110126_115001.jpg"
)

var bg = context.Background()

type env struct {
	t     *testing.T
	st    *store.Store
	blobs store.Blobs
	chars *characters.Service
	pub   http.Handler
	adm   http.Handler
	admin *Admin
	logs  *bytes.Buffer
	clock *time.Time
	seq   uint64
	gate  *openreg.Gate
	// freePercent is the free space of the data disk that the gate sees.
	freePercent float64
}

// newEnv builds the public handler (API and pages) and the admin handler over one store, one blob folder and one
// characters service, as the server does.
func newEnv(t *testing.T) *env {
	t.Helper()
	return newEnvWith(t, nil)
}

func newEnvWith(t *testing.T, wrap func(store.Blobs) store.Blobs) *env {
	t.Helper()
	data := t.TempDir()
	cfg, err := config.Load(func(k string) string {
		return map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_SITE_URL": "http://localhost:8080"}[k]
	})
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1794000000, 0)
	e := &env{t: t, logs: &bytes.Buffer{}, clock: &now, freePercent: 50}
	if e.st, err = store.Open(filepath.Join(data, "memories.db")); err != nil {
		t.Fatal(err)
	}
	e.st.SetClock(func() time.Time { return *e.clock })
	t.Cleanup(func() { e.st.Close() })
	disk, err := store.NewDiskBlobs(data)
	if err != nil {
		t.Fatal(err)
	}
	e.blobs = disk
	if wrap != nil {
		e.blobs = wrap(disk)
	}
	log := slog.New(slog.NewJSONHandler(e.logs, nil))
	e.chars = characters.New(e.st, e.blobs, log)

	web := t.TempDir()
	for name, body := range map[string]string{
		"index.html": "<!doctype html><html lang=\"en\"><title>Memories</title><body>viewer</body>",
		"app.js":     "//", "kinds.js": "//", "style.css": "/**/",
	} {
		if err := os.WriteFile(filepath.Join(web, name), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	static, err := site.New(site.Options{Name: "Test"})
	if err != nil {
		t.Fatal(err)
	}
	pages, err := site.NewPages(web, e.st, e.blobs, static.NotFound(), log)
	if err != nil {
		t.Fatal(err)
	}
	if err := e.st.SeedOpen(bg, cfg.Registration == config.RegistrationOpen); err != nil {
		t.Fatal(err)
	}
	e.gate = openreg.New(e.st, t.TempDir(), log)
	e.gate.SetDiskProbe(func(string) (float64, bool) { return e.freePercent, true })
	if _, err := e.gate.Refresh(bg); err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	api.New(cfg, e.st, e.chars, e.gate, log).Routes(mux)
	pages.Routes(mux)
	e.pub = mux

	e.admin, err = New(Options{
		Addr: adminHost, SiteURL: cfg.SiteURL, Store: e.st, Chars: e.chars, Gate: e.gate,
		DataLimit: cfg.MaxDataBytesPerKey, ShotLimit: cfg.MaxShotBytesPerKey, NotFound: static.NotFound(), Log: log,
	})
	if err != nil {
		t.Fatal(err)
	}
	e.admin.now = func() time.Time { return *e.clock }
	e.adm = e.admin.Handler()
	return e
}

func (e *env) advance(d time.Duration) { *e.clock = e.clock.Add(d) }

// client is one app key.
type client struct {
	priv ed25519.PrivateKey
	n    byte
	seq  uint64
}

func newClient(n byte) *client {
	return &client{priv: ed25519.NewKeyFromSeed(bytes.Repeat([]byte{n}, 32)), n: n}
}

func (c *client) public() []byte { return c.priv.Public().(ed25519.PublicKey) }

func (c *client) fingerprint() string { return store.Fingerprint(c.public()) }

func raw(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// signed sends a signed request to the public handler.
func (e *env) signed(c *client, method, target string, body []byte, hdr ...string) *httptest.ResponseRecorder {
	e.t.Helper()
	c.seq++
	nonce := make([]byte, 16)
	nonce[0] = c.n
	binary.BigEndian.PutUint64(nonce[8:], c.seq)
	ts := e.clock.Unix()
	msg := auth.SignedString(method, target, ts, raw(nonce), body)
	req := httptest.NewRequest(method, target, bytes.NewReader(body))
	req.RemoteAddr = "192.0.2." + strconv.Itoa(int(c.n)) + ":4000"
	req.Header.Set(auth.HeaderKey, raw(c.public()))
	req.Header.Set(auth.HeaderTime, strconv.FormatInt(ts, 10))
	req.Header.Set(auth.HeaderNonce, raw(nonce))
	req.Header.Set(auth.HeaderSignature, raw(ed25519.Sign(c.priv, []byte(msg))))
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	rec := httptest.NewRecorder()
	e.pub.ServeHTTP(rec, req)
	return rec
}

func (e *env) register(c *client, invite string) *httptest.ResponseRecorder {
	return e.signed(c, "POST", "/api/v1/register", []byte(`{"invite":"`+invite+`"}`))
}

// registered registers a new key with a new invite and returns it with its store row. An invite makes a key that can
// upload screenshots.
func (e *env) registered(n byte) (*client, store.Key) {
	e.t.Helper()
	c := newClient(n)
	_, code, err := e.st.CreateInvite(bg, "", time.Hour)
	if err != nil {
		e.t.Fatal(err)
	}
	if rec := e.register(c, code); rec.Code != http.StatusCreated {
		e.t.Fatalf("registration: %d %s", rec.Code, rec.Body)
	}
	return c, e.row(c)
}

func (e *env) row(c *client) store.Key {
	e.t.Helper()
	k, err := e.st.KeyByPublic(bg, c.public())
	if err != nil {
		e.t.Fatal(err)
	}
	return k
}

func readFile(t testing.TB, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func decodeAny(t testing.TB, b []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

func jsonl(t testing.TB, b []byte) []any {
	t.Helper()
	out := []any{}
	for _, line := range bytes.Split(bytes.TrimSpace(b), []byte("\n")) {
		if len(line) > 0 {
			out = append(out, decodeAny(t, line))
		}
	}
	return out
}

// uploadBody is the gzip request body of a folder of testdata/expected.
func uploadBody(t testing.TB, id string) []byte {
	t.Helper()
	dir := filepath.Join(expectedDir, id)
	body, err := json.Marshal(map[string]any{
		"character": decodeAny(t, readFile(t, filepath.Join(dir, "character.json"))),
		"journey":   jsonl(t, readFile(t, filepath.Join(dir, "journey.jsonl"))),
		"trail":     jsonl(t, readFile(t, filepath.Join(dir, "trail.jsonl"))),
	})
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	zw.Write(body)
	zw.Close()
	return buf.Bytes()
}

func (e *env) upload(c *client, id string) *httptest.ResponseRecorder {
	e.t.Helper()
	return e.signed(c, "POST", "/api/v1/characters", uploadBody(e.t, id), "Content-Encoding", "gzip")
}

func (e *env) mustUpload(c *client, id string) {
	e.t.Helper()
	if rec := e.upload(c, id); rec.Code != http.StatusOK {
		e.t.Fatalf("upload %s: %d %s", id, rec.Code, rec.Body)
	}
}

func (e *env) putShot(c *client, path, file string) *httptest.ResponseRecorder {
	e.t.Helper()
	return e.signed(c, "PUT", "/api/v1/characters/"+path+"/screenshots/"+file, readFile(e.t, filepath.Join(imagesDir, "small.jpg")))
}

func (e *env) errorCode(rec *httptest.ResponseRecorder) string {
	var a struct {
		Error string `json:"error"`
	}
	json.Unmarshal(rec.Body.Bytes(), &a)
	return a.Error
}

// page fetches a public page.
func (e *env) page(path string) int {
	rec := httptest.NewRecorder()
	e.pub.ServeHTTP(rec, httptest.NewRequest("GET", "/"+path+"/", nil))
	return rec.Code
}

func (e *env) invites() []store.InviteRow {
	e.t.Helper()
	l, err := e.st.ListInvites(bg, "", 1, 1000)
	if err != nil {
		e.t.Fatal(err)
	}
	return l.Rows
}

func (e *env) claim(path string) (store.Claim, error) {
	s := strings.Split(path, "/")
	return e.st.ClaimByPath(bg, s[0], s[1], s[2], s[3])
}

func (e *env) stored(claim store.Claim, name string) []byte {
	e.t.Helper()
	f, err := e.blobs.Open(bg, strconv.FormatInt(claim.ID, 10)+"/"+name)
	if err != nil {
		e.t.Fatal(err)
	}
	defer f.Close()
	b, err := io.ReadAll(f)
	if err != nil {
		e.t.Fatal(err)
	}
	return b
}

func (e *env) hasFile(claim store.Claim, name string) bool {
	_, err := e.blobs.Open(bg, strconv.FormatInt(claim.ID, 10)+"/"+name)
	return !errors.Is(err, fs.ErrNotExist)
}

// browser plays the admin's browser: it keeps cookies and sends the Host header of the tunnel.
type browser struct {
	e       *env
	host    string
	cookies map[string]string
}

func (e *env) browser() *browser {
	return &browser{e: e, host: adminHost, cookies: map[string]string{}}
}

func (b *browser) do(method, target string, form url.Values, mod ...func(*http.Request)) *httptest.ResponseRecorder {
	b.e.t.Helper()
	var body io.Reader
	if form != nil {
		body = strings.NewReader(form.Encode())
	}
	req := httptest.NewRequest(method, target, body)
	req.Host = b.host
	if form != nil {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	for name, value := range b.cookies {
		req.AddCookie(&http.Cookie{Name: name, Value: value})
	}
	for _, m := range mod {
		m(req)
	}
	rec := httptest.NewRecorder()
	b.e.adm.ServeHTTP(rec, req)
	for _, c := range rec.Result().Cookies() {
		if c.MaxAge < 0 {
			delete(b.cookies, c.Name)
		} else {
			b.cookies[c.Name] = c.Value
		}
	}
	return rec
}

func (b *browser) get(target string) *httptest.ResponseRecorder { return b.do("GET", target, nil) }

// token loads a page to get the CSRF cookie, and returns the token.
func (b *browser) token() string {
	b.e.t.Helper()
	if b.cookies[csrfCookie] == "" {
		b.get("/keys")
	}
	return b.cookies[csrfCookie]
}

// post sends a form with the CSRF token of this browser.
func (b *browser) post(path string, form url.Values) *httptest.ResponseRecorder {
	b.e.t.Helper()
	form.Set("csrf", b.token())
	return b.do("POST", path, form)
}

// act sends a form, checks the redirect and returns the text of the page that it leads to.
func (b *browser) act(path string, form url.Values) string {
	b.e.t.Helper()
	rec := b.post(path, form)
	if rec.Code != http.StatusSeeOther {
		b.e.t.Fatalf("POST %s = %d %s; want a 303 redirect", path, rec.Code, rec.Body)
	}
	next := b.get(rec.Header().Get("Location"))
	if next.Code != http.StatusOK {
		b.e.t.Fatalf("GET %s = %d", rec.Header().Get("Location"), next.Code)
	}
	return next.Body.String()
}

func form(kv ...string) url.Values {
	v := url.Values{}
	for i := 0; i+1 < len(kv); i += 2 {
		v.Set(kv[i], kv[i+1])
	}
	return v
}

func id(k store.Key) string { return strconv.FormatInt(k.ID, 10) }

func mustContain(t *testing.T, body string, want ...string) {
	t.Helper()
	for _, w := range want {
		if !strings.Contains(body, w) {
			t.Errorf("the page lacks %q:\n%s", w, body)
		}
	}
}

func TestHostCheck(t *testing.T) {
	e := newEnv(t)
	for _, tc := range []struct {
		host string
		want int
	}{
		{"127.0.0.1:8081", http.StatusOK},
		{"localhost:8081", http.StatusOK},
		{"LOCALHOST:8081", http.StatusOK},
		{"evil.example:8081", http.StatusForbidden},
		{"127.0.0.1.evil.example:8081", http.StatusForbidden},
		{"127.0.0.1:9999", http.StatusForbidden},
		{"127.0.0.1", http.StatusForbidden},
		{"[::1]:8081", http.StatusForbidden},
		{"", http.StatusForbidden},
	} {
		b := e.browser()
		b.host = tc.host
		rec := b.get("/keys")
		if rec.Code != tc.want {
			t.Errorf("GET with Host %q = %d, want %d", tc.host, rec.Code, tc.want)
		}
		if tc.want == http.StatusForbidden && !strings.Contains(rec.Body.String(), "127.0.0.1:8081") {
			t.Errorf("Host %q: the 403 does not say how to open the page: %q", tc.host, rec.Body)
		}
	}

	// A rebinding page sends a correct token with a foreign Host: it must still change nothing.
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	b := e.browser()
	token := b.token()
	b.host = "evil.example:8081"
	rec := b.do("POST", "/requests/approve", form("csrf", token, "key", id(k)))
	if rec.Code != http.StatusForbidden {
		t.Errorf("POST with a foreign Host = %d, want 403", rec.Code)
	}
	if got := e.row(c).Screenshots; got != store.ShotsPending {
		t.Errorf("screenshots = %q after a blocked POST, want pending", got)
	}
}

func TestCSRFProtection(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	b := e.browser()
	token := b.token()
	other := e.browser().token()
	if token == other {
		t.Fatal("two browsers got the same token")
	}
	withOrigin := func(o string) func(*http.Request) { return func(r *http.Request) { r.Header.Set("Origin", o) } }

	cases := []struct {
		name string
		do   func() *httptest.ResponseRecorder
	}{
		{"no cookie and no field", func() *httptest.ResponseRecorder {
			return e.browser().do("POST", "/requests/approve", form("key", id(k)))
		}},
		{"a field with no cookie", func() *httptest.ResponseRecorder {
			return e.browser().do("POST", "/requests/approve", form("csrf", token, "key", id(k)))
		}},
		{"a cookie with no field", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve", form("key", id(k)))
		}},
		{"a token from another session", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve", form("csrf", other, "key", id(k)))
		}},
		{"a made-up token in both places", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve", form("csrf", "short", "key", id(k)), func(r *http.Request) {
				r.Header.Del("Cookie")
				r.AddCookie(&http.Cookie{Name: csrfCookie, Value: "short"})
			})
		}},
		{"a foreign Origin", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve", form("csrf", token, "key", id(k)), withOrigin("http://evil.example"))
		}},
		{"an Origin with the same host name and another port", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve", form("csrf", token, "key", id(k)), withOrigin("http://127.0.0.1:9"))
		}},
		{"a null Origin", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve", form("csrf", token, "key", id(k)), withOrigin("null"))
		}},
		{"an https Origin", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve", form("csrf", token, "key", id(k)), withOrigin("https://"+adminHost))
		}},
		{"a token in the query only", func() *httptest.ResponseRecorder {
			return b.do("POST", "/requests/approve?csrf="+token, form("key", id(k)))
		}},
	}
	for _, tc := range cases {
		rec := tc.do()
		if rec.Code != http.StatusForbidden {
			t.Errorf("%s: status %d, want 403", tc.name, rec.Code)
		}
		if got := e.row(c).Screenshots; got != store.ShotsPending {
			t.Fatalf("%s: screenshots = %q, a blocked request changed the key", tc.name, got)
		}
	}

	rec := b.do("POST", "/requests/approve", form("csrf", token, "key", id(k)), withOrigin("http://"+adminHost))
	if rec.Code != http.StatusSeeOther {
		t.Fatalf("a valid request with the matching Origin = %d, want 303", rec.Code)
	}
	if got := e.row(c).Screenshots; got != store.ShotsApproved {
		t.Errorf("screenshots = %q, want approved", got)
	}
}

func TestChangesNeedPOST(t *testing.T) {
	e := newEnv(t)
	b := e.browser()
	for _, path := range []string{"/requests/approve", "/keys/revoke", "/invites/create", "/characters/delete"} {
		if rec := b.get(path); rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404: a change is a POST only", path, rec.Code)
		}
	}
}

func TestPagesAreStaticHTMLWithAStrictCookie(t *testing.T) {
	e := newEnv(t)
	b := e.browser()
	for _, path := range []string{"/requests", "/keys", "/invites", "/characters"} {
		rec := b.get(path)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d", path, rec.Code)
		}
		body := rec.Body.String()
		mustContain(t, body, "Requests", "Keys", "Invites", "Characters", `href="/admin.css"`)
		for _, bad := range []string{"<script", "javascript:", " onclick=", "http://", "https://"} {
			if strings.Contains(body, bad) {
				t.Errorf("%s contains %q: the page must have no script and no external resource", path, bad)
			}
		}
		if ct := rec.Header().Get("Content-Type"); ct != "text/html; charset=utf-8" {
			t.Errorf("%s Content-Type = %q", path, ct)
		}
		if cc := rec.Header().Get("Cache-Control"); cc != "no-store" {
			t.Errorf("%s Cache-Control = %q, want no-store", path, cc)
		}
		if rp := rec.Header().Get("Referrer-Policy"); rp != "same-origin" {
			t.Errorf("%s Referrer-Policy = %q, want same-origin so a form POST carries its real Origin", path, rp)
		}
	}

	rec := e.browser().get("/keys")
	var found bool
	for _, c := range rec.Result().Cookies() {
		if c.Name != csrfCookie {
			continue
		}
		found = true
		if !c.HttpOnly || c.SameSite != http.SameSiteStrictMode || c.Path != "/" || !validToken(c.Value) {
			t.Errorf("CSRF cookie = %+v, want HttpOnly, SameSite=Strict, Path=/ and a 32-byte token", c)
		}
	}
	if !found {
		t.Error("the page set no CSRF cookie")
	}

	// A browser keeps its token across pages.
	first := b.cookies[csrfCookie]
	b.get("/invites")
	if b.cookies[csrfCookie] != first {
		t.Error("the token changed between two pages")
	}

	css := b.get("/admin.css")
	if css.Code != http.StatusOK || !strings.HasPrefix(css.Header().Get("Content-Type"), "text/css") || strings.Contains(css.Body.String(), "url(") {
		t.Errorf("admin.css = %d %q", css.Code, css.Header().Get("Content-Type"))
	}
	if rec := b.get("/"); rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "/requests" {
		t.Errorf("GET / = %d to %q, want a redirect to /requests", rec.Code, rec.Header().Get("Location"))
	}
	if rec := b.get("/nothing-here"); rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "html") {
		t.Errorf("GET /nothing-here = %d, want the generic 404 page", rec.Code)
	}
}

func TestApproveAndDenyScreenshots(t *testing.T) {
	e := newEnv(t)
	a, ka := e.registered(1)
	b2, kb := e.registered(2)
	c3, kc := e.registered(3)
	for _, c := range []*client{a, b2} {
		if rec := e.signed(c, "POST", "/api/v1/screenshots/request", nil); rec.Code != http.StatusOK {
			t.Fatal(rec.Body)
		}
	}
	br := e.browser()

	page := br.get("/requests").Body.String()
	mustContain(t, page, a.fingerprint(), b2.fingerprint(), `action="/requests/approve"`, `action="/requests/deny"`)
	if strings.Contains(page, c3.fingerprint()) {
		t.Error("a key with no request is on the Requests page")
	}

	msg := br.act("/requests/approve", form("key", id(ka)))
	mustContain(t, msg, "Screenshots approved for key "+a.fingerprint())
	if got := e.row(a).Screenshots; got != store.ShotsApproved {
		t.Errorf("approved key = %q", got)
	}
	if strings.Contains(msg, `value="`+id(ka)+`"`) && strings.Contains(msg, a.fingerprint()+"</code>") {
		t.Error("the approved key is still on the Requests page")
	}

	msg = br.act("/requests/deny", form("key", id(kb)))
	mustContain(t, msg, "Screenshots denied for key "+b2.fingerprint())
	if got := e.row(b2).Screenshots; got != store.ShotsDenied {
		t.Errorf("denied key = %q", got)
	}

	// A double submit and a stale form change nothing.
	msg = br.act("/requests/approve", form("key", id(ka)))
	mustContain(t, msg, "no pending request any more")
	msg = br.act("/requests/approve", form("key", id(kb)))
	mustContain(t, msg, "no pending request any more")
	if got := e.row(b2).Screenshots; got != store.ShotsDenied {
		t.Errorf("a stale approve moved a denied key to %q", got)
	}
	msg = br.act("/requests/approve", form("key", id(kc)))
	mustContain(t, msg, "no pending request any more")
	if got := e.row(c3).Screenshots; got != store.ShotsNone {
		t.Errorf("an approve of a key with no request set %q", got)
	}

	// The denied key may ask again, and then it is listed again.
	e.signed(b2, "POST", "/api/v1/screenshots/request", nil)
	mustContain(t, br.get("/requests").Body.String(), b2.fingerprint())

	for _, bad := range []string{"", "x", "99999", "-1"} {
		msg = br.act("/requests/approve", form("key", bad))
		mustContain(t, msg, "That key does not exist")
	}
}

func TestApproveOfARevokedKeyChangesNothing(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	if err := e.st.RevokeKey(bg, k.ID); err != nil {
		t.Fatal(err)
	}
	br := e.browser()
	mustContain(t, br.act("/requests/approve", form("key", id(k))), "no pending request any more")
	if got := e.row(c).Screenshots; got != store.ShotsPending {
		t.Errorf("screenshots = %q, want it unchanged", got)
	}
	if strings.Contains(br.get("/requests").Body.String(), c.fingerprint()) {
		t.Error("a revoked key is on the Requests page")
	}
}

func TestKeysPageShowsTheKeyFigures(t *testing.T) {
	e := newEnv(t)
	_, code, err := e.st.CreateInvite(bg, "for Ana", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	c := newClient(1)
	if _, err := e.st.Register(bg, store.RegisterInput{Public: c.public(), Nonce: bytes.Repeat([]byte{1}, 16), Invite: code}); err != nil {
		t.Fatal(err)
	}
	e.mustUpload(c, "eu-brumamar-nandu")
	claim, _ := e.claim(brumamar)

	page := e.browser().get("/keys").Body.String()
	mustContain(t, page, c.fingerprint(), "for Ana", "none", `<a href="/characters?q=`+c.fingerprint()+`">1</a>`,
		`action="/keys/revoke"`, `action="/keys/screenshots"`,
		"This blocks the key and deletes all its characters and screenshots.")
	if strings.Contains(page, "revoke-clean") {
		t.Error("the page still offers the revoke that keeps the characters")
	}
	if !strings.Contains(page, "KiB") {
		t.Errorf("the page shows no data size for %d bytes:\n%s", claim.DataBytes, page)
	}
}

func TestRevokeScreenshotsStripsRecordsAndFiles(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	br := e.browser()
	br.act("/requests/approve", form("key", id(k)))
	e.mustUpload(c, "eu-brumamar-nandu")
	e.mustUpload(c, "eu-los-errantes-nandu")
	for _, f := range []string{shotA, shotB} {
		if rec := e.putShot(c, brumamar, f); rec.Code != http.StatusCreated {
			t.Fatalf("screenshot %s: %d %s", f, rec.Code, rec.Body)
		}
	}
	claim, _ := e.claim(brumamar)
	if claim.ShotBytes == 0 || !e.hasFile(claim, "screenshots/"+shotA) {
		t.Fatal("the screenshots were not stored")
	}
	before := jsonl(t, e.stored(claim, "journey.jsonl"))
	trailBefore := e.stored(claim, "trail.jsonl")
	charBefore := e.stored(claim, "character.json")

	msg := br.act("/keys/screenshots", form("key", id(k)))
	mustContain(t, msg, "Screenshots are revoked for key "+c.fingerprint(), "2 characters")
	if got := e.row(c).Screenshots; got != store.ShotsDenied {
		t.Errorf("state = %q, want denied", got)
	}

	claim, _ = e.claim(brumamar)
	if claim.ShotBytes != 0 {
		t.Errorf("shot_bytes = %d, want 0", claim.ShotBytes)
	}
	for _, f := range []string{shotA, shotB} {
		if e.hasFile(claim, "screenshots/"+f) {
			t.Errorf("the file %s stayed", f)
		}
		if _, err := e.st.ShotOf(bg, claim.ID, f); !errors.Is(err, store.ErrNotFound) {
			t.Errorf("the row of %s stayed: %v", f, err)
		}
	}
	after := jsonl(t, e.stored(claim, "journey.jsonl"))
	if len(after) != len(before) {
		t.Fatalf("records: %d, want %d", len(after), len(before))
	}
	stripped := 0
	for i, rec := range before {
		want := rec.(map[string]any)
		if _, ok := want["screenshot"]; ok {
			stripped++
			delete(want, "screenshot")
		}
		got := after[i].(map[string]any)
		if _, ok := got["screenshot"]; ok {
			t.Errorf("record %d still has a screenshot field", i)
		}
		wantJSON, _ := json.Marshal(want)
		gotJSON, _ := json.Marshal(got)
		if string(wantJSON) != string(gotJSON) {
			t.Errorf("record %d changed beyond the screenshot field:\n got %s\nwant %s", i, gotJSON, wantJSON)
		}
	}
	if stripped != 2 {
		t.Errorf("the fixture had %d screenshot records, want 2", stripped)
	}
	if !bytes.Equal(e.stored(claim, "trail.jsonl"), trailBefore) || !bytes.Equal(e.stored(claim, "character.json"), charBefore) {
		t.Error("the trail or the character file changed")
	}
	var entry struct {
		Screenshots int `json:"screenshots"`
		Steps       int `json:"steps"`
	}
	if err := json.Unmarshal(e.stored(claim, "entry.json"), &entry); err != nil || entry.Screenshots != 0 || entry.Steps != len(before) {
		t.Errorf("entry.json = %+v, %v; want 0 screenshots and %d steps", entry, err, len(before))
	}
	total := int64(len(e.stored(claim, "journey.jsonl")) + len(e.stored(claim, "trail.jsonl")) +
		len(e.stored(claim, "character.json")) + len(e.stored(claim, "entry.json")))
	if claim.DataBytes != total || claim.Steps != int64(len(before)) {
		t.Errorf("claim = %d bytes, %d steps; want %d, %d", claim.DataBytes, claim.Steps, total, len(before))
	}

	// The key can not upload a screenshot any more, and a new upload does not bring the field back.
	if rec := e.putShot(c, brumamar, shotA); rec.Code != http.StatusForbidden {
		t.Errorf("screenshot after revoke = %d, want 403", rec.Code)
	}
	e.mustUpload(c, "eu-brumamar-nandu")
	claim, _ = e.claim(brumamar)
	if strings.Contains(string(e.stored(claim, "journey.jsonl")), `"screenshot"`) {
		t.Error("an upload after the revoke put the screenshot fields back")
	}
	if e.page(brumamar) == http.StatusNotFound {
		t.Error("the character page is gone; revoke screenshots must keep the character")
	}

	// A second run is harmless.
	if _, err := e.claim(errantes); err != nil {
		t.Errorf("the other character is gone: %v", err)
	}
	mustContain(t, br.act("/keys/screenshots", form("key", id(k))), "Screenshots are revoked for key")
}

func TestRevokeScreenshotsLeavesOtherKeysAlone(t *testing.T) {
	e := newEnv(t)
	a, ka := e.registered(1)
	b2, kb := e.registered(2)
	br := e.browser()
	for _, p := range []struct {
		c *client
		k store.Key
	}{{a, ka}, {b2, kb}} {
		e.signed(p.c, "POST", "/api/v1/screenshots/request", nil)
		br.act("/requests/approve", form("key", id(p.k)))
	}
	e.mustUpload(a, "eu-brumamar-nandu")
	e.mustUpload(b2, "eu-los-errantes-nandu")
	br.act("/keys/screenshots", form("key", id(ka)))
	if got := e.row(b2).Screenshots; got != store.ShotsApproved {
		t.Errorf("another key's state = %q, want approved", got)
	}
	claim, _ := e.claim(errantes)
	if !bytes.Equal(e.stored(claim, "journey.jsonl"), readFile(t, filepath.Join(expectedDir, "eu-los-errantes-nandu", "journey.jsonl"))) {
		t.Error("another key's journey changed")
	}
}

func TestRevokedKeyIsRefusedEverywhere(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	e.mustUpload(c, "eu-brumamar-nandu")
	br := e.browser()

	msg := br.act("/keys/revoke", form("key", id(k)))
	mustContain(t, msg, "Key "+c.fingerprint()+" is revoked and 1 character deleted")

	for name, rec := range map[string]*httptest.ResponseRecorder{
		"upload":   e.upload(c, "eu-brumamar-nandu"),
		"delete":   e.signed(c, "DELETE", "/api/v1/characters/"+brumamar, nil),
		"me":       e.signed(c, "GET", "/api/v1/me", nil),
		"register": e.register(c, ""),
		"request":  e.signed(c, "POST", "/api/v1/screenshots/request", nil),
		"shot":     e.putShot(c, brumamar, shotA),
	} {
		if rec.Code != http.StatusForbidden || e.errorCode(rec) != "key_revoked" {
			t.Errorf("%s by a revoked key = %d %s, want 403 key_revoked", name, rec.Code, rec.Body)
		}
	}
	if _, err := e.claim(brumamar); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("the character stayed after the revoke: %v", err)
	}
	if e.page(brumamar) != http.StatusNotFound {
		t.Error("the character page is still served after the revoke")
	}
	if page := br.get("/keys").Body.String(); !strings.Contains(page, "revoked") || strings.Contains(page, `action="/keys/revoke"`) {
		t.Error("the Keys page does not show the key as revoked, or still offers Revoke key for a key with no characters")
	}
	if _, err := e.claim(brumamar); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("an upload by the revoked key made a claim: %v", err)
	}
}

// uploadAs uploads a fixture character under another name and GUID, so that one test can have several paths.
func (e *env) uploadAs(c *client, id, name, guid string) *httptest.ResponseRecorder {
	e.t.Helper()
	dir := filepath.Join(expectedDir, id)
	ch := decodeAny(e.t, readFile(e.t, filepath.Join(dir, "character.json"))).(map[string]any)
	ch["name"], ch["guid"] = name, guid
	body, err := json.Marshal(map[string]any{
		"character": ch,
		"journey":   jsonl(e.t, readFile(e.t, filepath.Join(dir, "journey.jsonl"))),
		"trail":     jsonl(e.t, readFile(e.t, filepath.Join(dir, "trail.jsonl"))),
	})
	if err != nil {
		e.t.Fatal(err)
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	zw.Write(body)
	zw.Close()
	return e.signed(c, "POST", "/api/v1/characters", buf.Bytes(), "Content-Encoding", "gzip")
}

func TestRevokeKeyAndDeleteItsCharacters(t *testing.T) {
	e := newEnv(t)
	bad, kBad := e.registered(1)
	good, kGood := e.registered(2)
	e.mustUpload(bad, "eu-brumamar-nandu")
	e.mustUpload(bad, "eu-los-errantes-nandu")
	if rec := e.uploadAs(good, "eu-brumamar-nandu", "Zed", "Player-1-0000BEEF"); rec.Code != http.StatusOK {
		t.Fatal(rec.Body)
	}
	var badClaims []store.Claim
	for _, p := range []string{brumamar, errantes} {
		c, err := e.claim(p)
		if err != nil {
			t.Fatal(err)
		}
		badClaims = append(badClaims, c)
		if e.page(p) != http.StatusOK {
			t.Fatalf("%s has no page before the revoke", p)
		}
	}
	zed, _ := e.claim("wow/eu/brumamar/zed")

	br := e.browser()
	msg := br.act("/keys/revoke", form("key", id(kBad)))
	mustContain(t, msg, "Key "+bad.fingerprint()+" is revoked and 2 characters deleted")

	if !e.row(bad).Revoked {
		t.Error("the key is not revoked")
	}
	for i, p := range []string{brumamar, errantes} {
		if _, err := e.claim(p); !errors.Is(err, store.ErrNotFound) {
			t.Errorf("%s: claim stayed: %v", p, err)
		}
		if e.hasFile(badClaims[i], "journey.jsonl") || e.hasFile(badClaims[i], "entry.json") || e.hasFile(badClaims[i], "character.json") {
			t.Errorf("%s: files stayed", p)
		}
		if got := e.page(p); got != http.StatusNotFound {
			t.Errorf("%s page = %d, want 404", p, got)
		}
	}
	if rec := e.upload(bad, "eu-brumamar-nandu"); rec.Code != http.StatusForbidden || e.errorCode(rec) != "key_revoked" {
		t.Errorf("upload by the revoked key = %d %s", rec.Code, rec.Body)
	}
	// Another key's character is untouched, and the freed path is free to claim.
	if e.page("wow/eu/brumamar/zed") != http.StatusOK || !e.hasFile(zed, "journey.jsonl") {
		t.Error("another key's character was affected")
	}
	if e.row(good).Revoked {
		t.Error("another key was revoked")
	}
	if rec := e.uploadAs(good, "eu-brumamar-nandu", "Nandu", "Player-1-0000A001"); rec.Code != http.StatusOK {
		t.Errorf("a new key can not claim the freed path: %d %s", rec.Code, rec.Body)
	}
	_ = kGood

	// Run again on a revoked key with nothing left: it still works.
	mustContain(t, br.act("/keys/revoke", form("key", id(kBad))), "0 characters deleted")
}

func TestRevokeKeyDeletesTheScreenshotsToo(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	br := e.browser()
	br.act("/requests/approve", form("key", id(k)))
	e.mustUpload(c, "eu-brumamar-nandu")
	if rec := e.putShot(c, brumamar, shotA); rec.Code != http.StatusCreated {
		t.Fatalf("screenshot: %d %s", rec.Code, rec.Body)
	}
	claim, _ := e.claim(brumamar)
	if !e.hasFile(claim, "screenshots/"+shotA) {
		t.Fatal("the screenshot was not stored")
	}
	br.act("/keys/revoke", form("key", id(k)))
	if e.hasFile(claim, "screenshots/"+shotA) {
		t.Error("the screenshot file stayed")
	}
	if _, err := e.st.ShotOf(bg, claim.ID, shotA); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("the screenshot row stayed: %v", err)
	}
	if e.page(brumamar) != http.StatusNotFound {
		t.Error("the character page is still served")
	}
}

func TestAdminDeleteOfOneCharacterLeavesTheOthers(t *testing.T) {
	e := newEnv(t)
	c, _ := e.registered(1)
	e.mustUpload(c, "eu-brumamar-nandu")
	e.mustUpload(c, "eu-los-errantes-nandu")
	gone, _ := e.claim(brumamar)
	br := e.browser()

	mustContain(t, br.get("/characters").Body.String(), brumamar, errantes, `href="http://localhost:8080/`+brumamar+`/"`)
	msg := br.act("/characters/delete", form("path", brumamar))
	mustContain(t, msg, brumamar+" is deleted")
	if _, err := e.claim(brumamar); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("claim stayed: %v", err)
	}
	if e.hasFile(gone, "journey.jsonl") {
		t.Error("files stayed")
	}
	if e.page(brumamar) != http.StatusNotFound {
		t.Error("the deleted character still has a page")
	}
	if _, err := e.claim(errantes); err != nil || e.page(errantes) != http.StatusOK {
		t.Errorf("the other character was affected: %v", err)
	}
	if e.row(c).Revoked {
		t.Error("an admin delete revoked the key")
	}
	if rec := e.upload(c, "eu-brumamar-nandu"); rec.Code != http.StatusOK {
		t.Errorf("the owner can not upload the freed path: %d %s", rec.Code, rec.Body)
	}

	// A second submit and bad paths give a message, not an error page.
	br.act("/characters/delete", form("path", brumamar))
	mustContain(t, br.act("/characters/delete", form("path", brumamar)), "does not exist any more")
	for _, bad := range []string{"", "wow/eu/brumamar", "wow/eu/brumamar/../x", "wow/EU/brumamar/nandu", "../../etc/passwd/x"} {
		mustContain(t, br.act("/characters/delete", form("path", bad)), "path is not valid")
	}
}

func TestMoveClaimGivesTheCharacterToTheNewKey(t *testing.T) {
	e := newEnv(t)
	oldKey, _ := e.registered(1)
	newKey, kNew := e.registered(2)
	e.mustUpload(oldKey, "eu-brumamar-nandu")
	br := e.browser()

	if rec := e.upload(newKey, "eu-brumamar-nandu"); rec.Code != http.StatusConflict || e.errorCode(rec) != "claimed" {
		t.Fatalf("the new key before the move = %d %s, want 409 claimed", rec.Code, rec.Body)
	}
	msg := br.act("/characters/move", form("path", brumamar, "to", " "+strings.ToUpper(newKey.fingerprint())+" ", "q", "nandu"))
	mustContain(t, msg, brumamar+" now belongs to key "+newKey.fingerprint())
	claim, _ := e.claim(brumamar)
	if claim.KeyID != kNew.ID {
		t.Errorf("owner = %d, want %d", claim.KeyID, kNew.ID)
	}
	if rec := e.upload(newKey, "eu-brumamar-nandu"); rec.Code != http.StatusOK {
		t.Errorf("the new key after the move = %d %s, want 200", rec.Code, rec.Body)
	}
	if rec := e.upload(oldKey, "eu-brumamar-nandu"); rec.Code != http.StatusConflict || e.errorCode(rec) != "claimed" {
		t.Errorf("the old key after the move = %d %s, want 409 claimed", rec.Code, rec.Body)
	}
	if rec := e.signed(oldKey, "DELETE", "/api/v1/characters/"+brumamar, nil); rec.Code != http.StatusNotFound {
		t.Errorf("delete by the old key = %d, want 404", rec.Code)
	}
	if rec := e.signed(newKey, "GET", "/api/v1/me", nil); !strings.Contains(rec.Body.String(), brumamar) {
		t.Errorf("me of the new key lacks the character: %s", rec.Body)
	}
	if e.page(brumamar) != http.StatusOK {
		t.Error("the page went away with the move")
	}
}

func TestMoveClaimRefusals(t *testing.T) {
	e := newEnv(t)
	owner, kOwner := e.registered(1)
	revoked, kRevoked := e.registered(2)
	e.mustUpload(owner, "eu-brumamar-nandu")
	if err := e.st.RevokeKey(bg, kRevoked.ID); err != nil {
		t.Fatal(err)
	}
	br := e.browser()
	for _, tc := range []struct{ name, path, to, want string }{
		{"revoked target", brumamar, revoked.fingerprint(), "is revoked"},
		{"same key", brumamar, owner.fingerprint(), "owns " + brumamar + " already"},
		{"unknown fingerprint", brumamar, "0123456789abcdef", "No key has the fingerprint"},
		{"empty fingerprint", brumamar, "", "No key has the fingerprint"},
		{"missing character", errantes, owner.fingerprint(), "does not exist any more"},
		{"bad path", "wow/eu/x", owner.fingerprint(), "path is not valid"},
	} {
		mustContain(t, br.act("/characters/move", form("path", tc.path, "to", tc.to)), tc.want)
		if c, err := e.claim(brumamar); err != nil || c.KeyID != kOwner.ID {
			t.Fatalf("%s: the owner changed to %d (%v)", tc.name, c.KeyID, err)
		}
	}
}

func TestInviteIsShownOnceAndWorks(t *testing.T) {
	e := newEnv(t)
	br := e.browser()
	msg := br.act("/invites/create", form("note", "for Ana <b>x</b>", "days", "10"))
	mustContain(t, msg, "valid for 10 days", "only time the code is shown", "for Ana &lt;b&gt;x&lt;/b&gt;")
	m := regexpCode.FindStringSubmatch(msg)
	if m == nil {
		t.Fatalf("no code on the page after the create:\n%s", msg)
	}
	code := m[1]
	if strings.Contains(msg, "<b>x</b>") {
		t.Error("the note is not escaped")
	}

	// The page after a reload has no code, and the log and the URLs never had it.
	again := br.get("/invites").Body.String()
	if strings.Contains(again, code) || strings.Contains(again, strings.ReplaceAll(code, "-", "")) {
		t.Error("the code is shown a second time")
	}
	mustContain(t, again, "Unused", "for Ana")
	if strings.Contains(e.logs.String(), strings.ReplaceAll(code, "-", "")) || strings.Contains(e.logs.String(), code) {
		t.Error("the invite code is in the log")
	}
	if strings.Contains(e.logs.String(), br.cookies[csrfCookie]) {
		t.Error("the CSRF token is in the log")
	}

	// The code, with dashes and in lower case, registers a key.
	invite := e.pubWithInvite(strings.ToLower(code))
	if invite.Code != http.StatusCreated && invite.Code != http.StatusOK {
		t.Errorf("register with the shown code = %d %s", invite.Code, invite.Body)
	}
}

var regexpCode = regexpMust(`<code>([0-9A-Z]{4}(?:-[0-9A-Z]{4}){3})</code>`)

func (e *env) pubWithInvite(code string) *httptest.ResponseRecorder {
	c := newClient(9)
	return e.register(c, code)
}

func TestInviteStatesAndRevoke(t *testing.T) {
	e := newEnv(t)
	br := e.browser()
	create := func(note string) string {
		m := regexpCode.FindStringSubmatch(br.act("/invites/create", form("note", note)))
		if m == nil {
			t.Fatal("no code")
		}
		return m[1]
	}
	create("one-used")
	_, _, err := e.st.CreateInvite(bg, "one-expired", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	// The default is 30 days.
	var expires int64
	invs := e.invites()
	for _, i := range invs {
		if i.Note == "one-used" {
			expires = i.Expires - i.Created
		}
	}
	if expires != 30*24*3600 {
		t.Errorf("default validity = %d s, want 30 days", expires)
	}
	revokedCode := create("one-revoked")
	spend := func(code string, n byte) {
		// The server in these tests runs in open mode, where a code is ignored, so spend it in the store.
		if _, err := e.st.Register(bg, store.RegisterInput{Public: bytes.Repeat([]byte{n}, 32), Nonce: bytes.Repeat([]byte{n}, 16), Invite: code}); err != nil {
			t.Fatal(err)
		}
	}
	usedInv := e.invites()
	_ = usedInv
	spend(strings.ReplaceAll(create("one-spent"), "-", ""), 5)
	e.advance(2 * time.Hour)

	page := br.get("/invites").Body.String()
	mustContain(t, page, "Used by key "+store.Fingerprint(bytes.Repeat([]byte{5}, 32)), "Expired", "Unused", "one-revoked")

	var revokeID string
	invs = e.invites()
	for _, i := range invs {
		if i.Note == "one-revoked" {
			revokeID = strconv.FormatInt(i.ID, 10)
		}
	}
	mustContain(t, br.act("/invites/revoke", form("invite", revokeID)), "is revoked. Its code no longer works", "Revoked")
	// A revoke from a page that was open before the invite was spent keeps who spent it on the page.
	for _, i := range invs {
		if i.Note == "one-spent" {
			br.act("/invites/revoke", form("invite", strconv.FormatInt(i.ID, 10)))
		}
	}
	mustContain(t, br.get("/invites").Body.String(), "Used by key "+store.Fingerprint(bytes.Repeat([]byte{5}, 32)))
	if _, err := e.st.Register(bg, store.RegisterInput{Public: bytes.Repeat([]byte{7}, 32), Nonce: bytes.Repeat([]byte{7}, 16), Invite: revokedCode}); !errors.Is(err, store.ErrInviteInvalid) {
		t.Errorf("a revoked code registered a key: %v", err)
	}
	for _, bad := range []string{"", "x", "99999"} {
		mustContain(t, br.act("/invites/revoke", form("invite", bad)), "That invite does not exist")
	}
}

func TestInviteInputIsChecked(t *testing.T) {
	e := newEnv(t)
	br := e.browser()
	for _, days := range []string{"0", "-3", "366", "ten", "1.5"} {
		mustContain(t, br.act("/invites/create", form("days", days)), "Days valid must be a whole number from 1 to 365")
	}
	if invs := e.invites(); len(invs) != 0 {
		t.Errorf("a bad form made %d invites", len(invs))
	}
	long := strings.Repeat("a", 300) + "\x00\x07z"
	br.act("/invites/create", form("note", long, "days", "365"))
	invs := e.invites()
	if len(invs) != 1 || len([]rune(invs[0].Note)) != maxNoteRunes || strings.ContainsAny(invs[0].Note, "\x00\x07") {
		t.Errorf("note = %q, want %d printable runes", invs[0].Note, maxNoteRunes)
	}
	if got := groupCode("ABCDEFGHJKMNPQRS"); got != "ABCD-EFGH-JKMN-PQRS" {
		t.Errorf("groupCode = %q", got)
	}
}

func TestCharactersSearch(t *testing.T) {
	e := newEnv(t)
	c, _ := e.registered(1)
	e.mustUpload(c, "eu-brumamar-nandu")
	e.mustUpload(c, "eu-los-errantes-nandu")
	d, _ := e.registered(2)
	if rec := e.uploadAs(d, "eu-brumamar-nandu", "Zed", "Player-1-0000BEEF"); rec.Code != http.StatusOK {
		t.Fatal(rec.Body)
	}
	br := e.browser()
	has := func(q string, want, absent []string) {
		t.Helper()
		body := br.get("/characters?q=" + url.QueryEscape(q)).Body.String()
		for _, w := range want {
			if !strings.Contains(body, "<td><a href=\"http://localhost:8080/"+w+"/\"") {
				t.Errorf("search %q lacks %s", q, w)
			}
		}
		for _, a := range absent {
			if strings.Contains(body, "http://localhost:8080/"+a+"/") {
				t.Errorf("search %q shows %s", q, a)
			}
		}
	}
	all := []string{brumamar, errantes, "wow/eu/brumamar/zed"}
	has("", all, nil)
	has("zed", []string{"wow/eu/brumamar/zed"}, []string{brumamar, errantes})
	has("WOW/EU/LOS-ERRANTES", []string{errantes}, []string{brumamar})
	has("player-1-0000beef", []string{"wow/eu/brumamar/zed"}, []string{brumamar})
	has(c.fingerprint(), []string{brumamar, errantes}, []string{"wow/eu/brumamar/zed"})
	has(d.fingerprint(), []string{"wow/eu/brumamar/zed"}, []string{brumamar, errantes})
	has("0123456789abcdef", nil, all)
	has("%", nil, all)
	has("_", nil, all)
	has(`\`, nil, all)
	has("<script>", nil, all)
	body := br.get("/characters?q=" + url.QueryEscape("<script>alert(1)</script>")).Body.String()
	if strings.Contains(body, "<script>") || !strings.Contains(body, "No character matches") {
		t.Error("a search text is not escaped, or an empty result has no message")
	}
	has(strings.Repeat("z", 500), nil, all)
	long := br.get("/characters?q=" + url.QueryEscape(strings.Repeat("é", 300))).Body.String()
	if !strings.Contains(long, `value="`+strings.Repeat("é", maxQueryRunes)+`"`) {
		t.Error("a long search text is not cut at a whole character")
	}

}

func TestSearchBoxIsAPlainGetForm(t *testing.T) {
	e := newEnv(t)
	br := e.browser()
	for _, p := range []string{"requests", "keys", "invites", "characters"} {
		body := br.get("/" + p + "?q=ab%22c").Body.String()
		mustContain(t, body, `<form method="get" action="/`+p+`"`, `name="q"`, `value="ab&#34;c"`, "Clear search")
		if strings.Contains(body, "<script") || strings.Contains(body, "style=") {
			t.Errorf("%s page has a script or an inline style", p)
		}
	}
}

func TestNewChecksTheAddressAndWarnsOutsideLoopback(t *testing.T) {
	for _, tc := range []struct {
		addr string
		warn bool
	}{
		{"127.0.0.1:8081", false}, {"localhost:8081", false}, {"[::1]:8081", false}, {"127.1.2.3:8081", false},
		{"0.0.0.0:8081", true}, {":8081", true}, {"192.0.2.1:8081", true}, {"[::]:8081", true}, {"example.com:8081", true},
	} {
		var logs bytes.Buffer
		_, err := New(Options{Addr: tc.addr, Log: slog.New(slog.NewJSONHandler(&logs, nil))})
		if err != nil {
			t.Fatalf("%s: %v", tc.addr, err)
		}
		if got := strings.Contains(logs.String(), "not a loopback address"); got != tc.warn {
			t.Errorf("%s: warned = %v, want %v (%s)", tc.addr, got, tc.warn, logs.String())
		}
	}
	if _, err := New(Options{Addr: "nonsense", Log: slog.New(slog.NewJSONHandler(io.Discard, nil))}); err == nil {
		t.Error("New accepted an address with no port")
	}
	if isLoopback("nonsense") {
		t.Error("isLoopback accepted an address with no port")
	}
	// The Host check follows the configured port; with 0.0.0.0 in Docker, localhost and 127.0.0.1 still match.
	a, _ := New(Options{Addr: "0.0.0.0:9090", Log: slog.New(slog.NewJSONHandler(io.Discard, nil))})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/nothing", nil)
	req.Host = "localhost:9090"
	a.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("localhost:9090 = %d, want the 404 of the default handler", rec.Code)
	}
}

func TestActionsAreLoggedWithoutSecrets(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	e.mustUpload(c, "eu-brumamar-nandu")
	br := e.browser()
	br.act("/requests/approve", form("key", id(k)))
	br.act("/keys/screenshots", form("key", id(k)))
	br.act("/characters/delete", form("path", brumamar))
	br.act("/keys/revoke", form("key", id(k)))
	logs := e.logs.String()
	mustContain(t, logs, `"action":"screenshots approved"`, `"action":"revoke screenshots"`, `"action":"delete character"`,
		`"action":"revoke key"`, c.fingerprint(), brumamar)
	for _, secret := range []string{raw(c.public()), br.cookies[csrfCookie]} {
		if strings.Contains(logs, secret) {
			t.Errorf("the log holds a secret: %q", secret)
		}
	}
}

func TestFlashIsReadOnceAndExpires(t *testing.T) {
	e := newEnv(t)
	a := e.admin
	rec := httptest.NewRecorder()
	a.setFlash(rec, okMsg("hello"))
	cookie := rec.Result().Cookies()[0]
	read := func() *flash {
		req := httptest.NewRequest("GET", "/keys", nil)
		req.AddCookie(cookie)
		return a.takeFlash(httptest.NewRecorder(), req)
	}
	if f := read(); f == nil || f.Text != "hello" {
		t.Fatalf("first read = %+v", f)
	}
	if f := read(); f != nil {
		t.Errorf("second read = %+v, want nil", f)
	}

	rec = httptest.NewRecorder()
	a.setFlash(rec, okMsg("old"))
	cookie = rec.Result().Cookies()[0]
	e.advance(flashTTL + time.Second)
	if f := read(); f != nil {
		t.Errorf("an expired message was shown: %+v", f)
	}

	for range maxFlashes + 5 {
		a.setFlash(httptest.NewRecorder(), okMsg("x"))
	}
	if n := len(a.flash.m); n > maxFlashes {
		t.Errorf("%d messages are held, want at most %d", n, maxFlashes)
	}
	if f := a.takeFlash(httptest.NewRecorder(), httptest.NewRequest("GET", "/", nil)); f != nil {
		t.Error("a request with no cookie got a message")
	}
}

// failBlobs fails the operations that a test switches on.
type failBlobs struct {
	store.Blobs
	removeAll, write bool
}

func (f *failBlobs) RemoveAll(ctx context.Context, prefix string) error {
	if f.removeAll {
		return errors.New("disk error")
	}
	return f.Blobs.RemoveAll(ctx, prefix)
}

func (f *failBlobs) Write(ctx context.Context, path string, r io.Reader) error {
	if f.write {
		return errors.New("disk error")
	}
	return f.Blobs.Write(ctx, path, r)
}

func TestDiskFailuresGiveAMessageAndKeepTheRecords(t *testing.T) {
	var fb *failBlobs
	e := newEnvWith(t, func(b store.Blobs) store.Blobs { fb = &failBlobs{Blobs: b}; return fb })
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	br := e.browser()
	br.act("/requests/approve", form("key", id(k)))
	e.mustUpload(c, "eu-brumamar-nandu")

	fb.write = true
	mustContain(t, br.act("/keys/screenshots", form("key", id(k))), "removing them from every character failed")
	claim, _ := e.claim(brumamar)
	if !strings.Contains(string(e.stored(claim, "journey.jsonl")), `"screenshot"`) {
		t.Error("a failed write changed the stored records")
	}
	fb.write, fb.removeAll = false, true
	mustContain(t, br.act("/keys/revoke", form("key", id(k))), "deleting the rest failed", "Revoke the key again")
	if !e.row(c).Revoked {
		t.Error("a failed deletion left the key working")
	}
	if page := br.get("/keys").Body.String(); !strings.Contains(page, `action="/keys/revoke"`) {
		t.Error("a revoked key with characters left has no Revoke key button to retry")
	}
	mustContain(t, br.act("/keys/screenshots", form("key", id(k))), "removing them from every character failed", "Run this action again")
	mustContain(t, br.act("/characters/delete", form("path", brumamar)), "Could not delete the character")
	if _, err := e.claim(brumamar); err != nil {
		t.Errorf("the claim went although the files stayed: %v", err)
	}
	fb.removeAll = false
	if strings.Contains(e.logs.String(), "BEGIN") {
		t.Error("the log has raw data")
	}

	fb.write = false
	mustContain(t, br.act("/keys/screenshots", form("key", id(k))), "Screenshots are revoked")
	mustContain(t, br.act("/keys/revoke", form("key", id(k))), "1 character deleted")
}

func TestStoreFailuresGiveAPlainMessage(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	e.signed(c, "POST", "/api/v1/screenshots/request", nil)
	br := e.browser()
	br.token()
	e.st.Close()
	for _, p := range []string{"/requests", "/keys", "/invites", "/characters", "/characters?q=" + c.fingerprint()} {
		rec := br.get(p)
		if rec.Code != http.StatusInternalServerError || !strings.Contains(rec.Body.String(), "could not be built") || strings.Contains(rec.Body.String(), "sql") {
			t.Errorf("GET %s with a broken store = %d %q", p, rec.Code, rec.Body)
		}
	}
	for path, f := range map[string]url.Values{
		"/requests/approve":  form("key", id(k)),
		"/keys/revoke":       form("key", id(k)),
		"/keys/screenshots":  form("key", id(k)),
		"/invites/create":    form("days", "3"),
		"/invites/revoke":    form("invite", "1"),
		"/characters/delete": form("path", brumamar),
		"/characters/move":   form("path", brumamar, "to", c.fingerprint()),
	} {
		rec := br.post(path, f)
		if rec.Code != http.StatusSeeOther {
			t.Errorf("POST %s with a broken store = %d, want a redirect", path, rec.Code)
			continue
		}
		body := br.get(rec.Header().Get("Location"))
		if !strings.Contains(body.Body.String(), "notice error") && body.Code == http.StatusOK {
			t.Errorf("POST %s: no error message on the next page", path)
		}
	}
	if strings.Contains(e.logs.String(), "BEGIN") {
		t.Error("the log has raw data")
	}
}

func TestBodyOfAFormIsLimited(t *testing.T) {
	e := newEnv(t)
	br := e.browser()
	token := br.token()
	rec := br.do("POST", "/invites/create", form("csrf", token, "note", strings.Repeat("a", maxForm*2)))
	if rec.Code != http.StatusBadRequest {
		t.Errorf("a huge form = %d, want 400", rec.Code)
	}
}

func regexpMust(p string) *regexp.Regexp { return regexp.MustCompile(p) }
