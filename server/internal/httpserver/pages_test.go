package httpserver

import (
	"bytes"
	"compress/gzip"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"io"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

const (
	expectedDir = "../../../testdata/expected"
	imagesDir   = "../images/testdata"
	brumamar    = "/wow/eu/brumamar/nandu"
	errantes    = "/wow/eu/los-errantes/nandu"
	shotA       = "WoWScrnShot_110126_114820.jpg"
)

type fixture struct {
	t      *testing.T
	public http.Handler
	st     *store.Store
	priv   ed25519.PrivateKey
}

func newSite(t *testing.T) *fixture { return newSiteWith(t, nil) }

// newSiteWith is newSite with more settings.
func newSiteWith(t *testing.T, vars map[string]string) *fixture {
	t.Helper()
	env := map[string]string{"MEMORIES_REGISTRATION": "open"}
	maps.Copy(env, vars)
	public, _, st := newStack(t, loadConfig(t, env), io.Discard)
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	s := &fixture{t: t, public: public, st: st, priv: priv}
	if rec := s.signed("POST", "/api/v1/register", []byte("{}"), false); rec.Code != http.StatusCreated {
		t.Fatalf("register: %d %s", rec.Code, rec.Body)
	}
	return s
}

// approve gives the key of the fixture the screenshot approval, so that uploads keep the screenshot fields.
func (s *fixture) approve() {
	s.t.Helper()
	key, err := s.st.KeyByPublic(s.t.Context(), s.priv.Public().(ed25519.PublicKey))
	if err != nil {
		s.t.Fatal(err)
	}
	if err := s.st.SetScreenshots(s.t.Context(), key.ID, store.ShotsApproved); err != nil {
		s.t.Fatal(err)
	}
}

func (s *fixture) signed(method, target string, body []byte, gzipped bool) *httptest.ResponseRecorder {
	s.t.Helper()
	nonce := make([]byte, 16)
	rand.Read(nonce)
	enc := base64.RawURLEncoding.EncodeToString
	now := time.Now().Unix()
	req := httptest.NewRequest(method, target, bytes.NewReader(body))
	msg := auth.SignedString(method, target, now, enc(nonce), body)
	req.Header.Set(auth.HeaderKey, enc(s.priv.Public().(ed25519.PublicKey)))
	req.Header.Set(auth.HeaderTime, strconv.FormatInt(now, 10))
	req.Header.Set(auth.HeaderNonce, enc(nonce))
	req.Header.Set(auth.HeaderSignature, enc(ed25519.Sign(s.priv, []byte(msg))))
	if gzipped {
		req.Header.Set("Content-Encoding", "gzip")
	}
	rec := httptest.NewRecorder()
	s.public.ServeHTTP(rec, req)
	return rec
}

func readFixture(t *testing.T, dir, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(expectedDir, dir, name))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// upload sends one character folder of testdata/expected as the gzip of the upload object.
func (s *fixture) upload(dir string) {
	s.t.Helper()
	lines := func(name string) []json.RawMessage {
		out := []json.RawMessage{}
		for _, l := range bytes.Split(bytes.TrimSpace(readFixture(s.t, dir, name)), []byte("\n")) {
			if len(l) > 0 {
				out = append(out, l)
			}
		}
		return out
	}
	raw, err := json.Marshal(map[string]any{
		"character": json.RawMessage(readFixture(s.t, dir, "character.json")),
		"journey":   lines("journey.jsonl"),
		"trail":     lines("trail.jsonl"),
	})
	if err != nil {
		s.t.Fatal(err)
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	zw.Write(raw)
	zw.Close()
	if rec := s.signed("POST", "/api/v1/characters", buf.Bytes(), true); rec.Code != http.StatusOK {
		s.t.Fatalf("upload %s: %d %s", dir, rec.Code, rec.Body)
	}
}

func (s *fixture) get(target string, hdr ...string) *httptest.ResponseRecorder {
	req := httptest.NewRequest("GET", target, nil)
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	rec := httptest.NewRecorder()
	s.public.ServeHTTP(rec, req)
	return rec
}

func isNotFoundPage(rec *httptest.ResponseRecorder) bool {
	return rec.Code == http.StatusNotFound && strings.Contains(rec.Body.String(), "Page not found")
}

func TestCharacterPageAfterAnUpload(t *testing.T) {
	s := newSite(t)
	if rec := s.get(brumamar + "/"); !isNotFoundPage(rec) {
		t.Fatalf("page before the upload = %d, want the 404 page", rec.Code)
	}
	s.upload("eu-brumamar-nandu")

	rec := s.get(brumamar + "/")
	body := rec.Body.String()
	if rec.Code != http.StatusOK {
		t.Fatalf("page = %d", rec.Code)
	}
	for _, want := range []string{
		`<body data-entry="data/entry.json">`,
		"<title>Ñandú — Brumamar — Memories</title>",
		`href="/_/style.css"`, `src="/_/kinds.js"`, `src="/_/app.mjs"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("page lacks %q", want)
		}
	}
	checkPageHeaders(t, rec, "page")
	if rec.Header().Get("X-Robots-Tag") != "noindex, nofollow" || rec.Header().Get("Cache-Control") != "no-cache" || rec.Header().Get("ETag") == "" {
		t.Errorf("page headers: %v", rec.Header())
	}

	redirect := s.get(brumamar)
	if redirect.Code != http.StatusMovedPermanently || redirect.Header().Get("Location") != brumamar+"/" {
		t.Errorf("GET %s = %d, Location %q; want 301 to the slash form", brumamar, redirect.Code, redirect.Header().Get("Location"))
	}
	checkSecurityHeaders(t, redirect, "redirect")
}

func TestDataFilesServeTheStoredRecords(t *testing.T) {
	s := newSite(t)
	s.approve()
	for _, dir := range []string{"eu-brumamar-nandu", "eu-los-errantes-nandu"} {
		s.upload(dir)
	}
	for dir, path := range map[string]string{"eu-brumamar-nandu": brumamar, "eu-los-errantes-nandu": errantes} {
		for name, ct := range map[string]string{
			"character.json": "application/json", "journey.jsonl": "application/x-ndjson", "trail.jsonl": "application/x-ndjson",
		} {
			rec := s.get(path + "/data/" + name)
			if rec.Code != http.StatusOK || !bytes.Equal(rec.Body.Bytes(), readFixture(t, dir, name)) {
				t.Errorf("%s/data/%s: %d, the body differs from the fixture", path, name, rec.Code)
			}
			h := rec.Header()
			sum := sha256.Sum256(rec.Body.Bytes())
			if h.Get("Content-Type") != ct || h.Get("ETag") != `"`+hex.EncodeToString(sum[:])+`"` ||
				h.Get("X-Robots-Tag") != "noindex, nofollow" || h.Get("Cache-Control") != "no-cache" {
				t.Errorf("%s/data/%s: headers %v", path, name, h)
			}
			checkSecurityHeaders(t, rec, path+"/data/"+name)
			if again := s.get(path+"/data/"+name, "If-None-Match", h.Get("ETag")); again.Code != http.StatusNotModified {
				t.Errorf("%s/data/%s with its ETag = %d, want 304", path, name, again.Code)
			}
		}
	}
	// A character with no trail still serves the file, so the viewer loads.
	if rec := s.get(errantes + "/data/trail.jsonl"); rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != "" {
		t.Errorf("empty trail: %d %q", rec.Code, rec.Body)
	}

	rec := s.get(brumamar + "/data/entry.json")
	var entry map[string]any
	if rec.Code != http.StatusOK || json.Unmarshal(rec.Body.Bytes(), &entry) != nil {
		t.Fatalf("entry.json: %d %s", rec.Code, rec.Body)
	}
	for k, want := range map[string]any{
		"id": "wow/eu/brumamar/nandu", "path": ".", "character": "character.json", "journey": "journey.jsonl",
		"trail": "trail.jsonl", "name": "Ñandú", "steps": float64(15), "screenshots": float64(2),
	} {
		if entry[k] != want {
			t.Errorf("entry.%s = %v, want %v", k, entry[k], want)
		}
	}
}

func TestScreenshotIsServedAfterApproval(t *testing.T) {
	s := newSite(t)
	s.approve()
	s.upload("eu-brumamar-nandu")
	if rec := s.get(brumamar + "/data/screenshots/" + shotA); !isNotFoundPage(rec) {
		t.Fatalf("screenshot before its upload = %d, want the 404 page (the viewer shows a note)", rec.Code)
	}
	src, err := os.ReadFile(filepath.Join(imagesDir, "exif-gps.jpg"))
	if err != nil {
		t.Fatal(err)
	}
	if rec := s.signed("PUT", "/api/v1/characters"+brumamar+"/screenshots/"+shotA, src, false); rec.Code != http.StatusCreated {
		t.Fatalf("screenshot upload: %d %s", rec.Code, rec.Body)
	}
	rec := s.get(brumamar + "/data/screenshots/" + shotA)
	h := rec.Header()
	if rec.Code != http.StatusOK || h.Get("Content-Type") != "image/jpeg" || bytes.Contains(rec.Body.Bytes(), []byte("Exif")) ||
		h.Get("X-Robots-Tag") != "noindex, nofollow" || h.Get("ETag") == "" {
		t.Errorf("screenshot: %d %v", rec.Code, h)
	}
	checkSecurityHeaders(t, rec, "screenshot")
	if again := s.get(brumamar+"/data/screenshots/"+shotA, "If-None-Match", h.Get("ETag")); again.Code != http.StatusNotModified {
		t.Errorf("screenshot with its ETag = %d, want 304", again.Code)
	}
	var entry struct{ Screenshots int }
	json.Unmarshal(s.get(brumamar+"/data/entry.json").Body.Bytes(), &entry)
	if entry.Screenshots != 2 {
		t.Errorf("entry.screenshots = %d, want 2", entry.Screenshots)
	}
}

func TestUnknownCharacterPathsGiveTheGenericNotFoundPage(t *testing.T) {
	s := newSite(t)
	s.upload("eu-brumamar-nandu")
	generic := s.get("/nothing")
	if !isNotFoundPage(generic) {
		t.Fatal("no generic 404 page")
	}
	for _, p := range []string{
		"/WOW/eu/brumamar/nandu/", "/wow/EU/brumamar/nandu/", "/wow/eu/brumamar/Nandu/",
		brumamar + "/index.html", brumamar + "/data/memories.db", brumamar + "/data/%2e%2e/memories.db",
		brumamar + "/data/character.json/", brumamar + "/data/", brumamar + "/data/screenshots/" + shotA,
		"/wow/eu/brumamar/other/", "/wow/eu/brumamar/other/data/journey.jsonl", errantes + "/", errantes + "/data/entry.json",
	} {
		rec := s.get(p)
		if rec.Code == http.StatusMovedPermanently || rec.Code == http.StatusTemporaryRedirect {
			// The mux cleans the path first; the cleaned path must give the 404 page.
			rec = s.get(rec.Header().Get("Location"))
		}
		if !isNotFoundPage(rec) || rec.Body.String() != generic.Body.String() || rec.Header().Get("X-Robots-Tag") != "" {
			t.Errorf("GET %s = %d, want the generic 404 page", p, rec.Code)
		}
		checkSecurityHeaders(t, rec, p)
	}
}

func TestDeletedCharacterGivesTheNotFoundPage(t *testing.T) {
	s := newSite(t)
	s.upload("eu-brumamar-nandu")
	for _, p := range []string{"/", "/data/journey.jsonl"} {
		if rec := s.get(brumamar + p); rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d before the delete", p, rec.Code)
		}
	}
	if rec := s.signed("DELETE", "/api/v1/characters"+brumamar, nil, false); rec.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", rec.Code, rec.Body)
	}
	generic := s.get("/nothing").Body.String()
	for _, p := range []string{"/", "/data/journey.jsonl", "/data/entry.json"} {
		if rec := s.get(brumamar + p); !isNotFoundPage(rec) || rec.Body.String() != generic {
			t.Errorf("GET %s = %d after the delete, want the generic 404 page", p, rec.Code)
		}
	}
}

func TestViewerAssetsAreServedFromTheWebFolder(t *testing.T) {
	s := newSite(t)
	for path, ct := range map[string]string{
		"/_/app.mjs": "text/javascript", "/_/lib/format.mjs": "text/javascript", "/_/kinds.js": "text/javascript",
		"/_/style.css": "text/css", "/_/base.css": "text/css", "/_/icon.png": "image/png",
	} {
		rec := s.get(path)
		want, err := os.ReadFile(filepath.Join(realWebDir, strings.TrimPrefix(path, "/_/")))
		if err != nil {
			t.Fatal(err)
		}
		if rec.Code != http.StatusOK || !bytes.Equal(rec.Body.Bytes(), want) || !strings.HasPrefix(rec.Header().Get("Content-Type"), ct) {
			t.Errorf("GET %s: %d, type %q", path, rec.Code, rec.Header().Get("Content-Type"))
		}
		checkSecurityHeaders(t, rec, path)
		if again := s.get(path, "If-None-Match", rec.Header().Get("ETag")); again.Code != http.StatusNotModified {
			t.Errorf("GET %s with its ETag = %d, want 304", path, again.Code)
		}
	}
	for _, path := range []string{"/app.js", "/kinds.js", "/style.css"} {
		if rec := s.get(path); !isNotFoundPage(rec) {
			t.Errorf("GET %s = %d, want the 404 page", path, rec.Code)
		}
	}
	for _, path := range []string{"/_/test/format.test.mjs", "/_/test/fixtures/nandu/entry.json", "/_/characters/x.json"} {
		if rec := s.get(path); rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404: it is not a viewer file", path, rec.Code)
		}
	}
}

var assetRef = regexp.MustCompile(`(?:src|href)="([^"]+)"`)

// The page of a character loads only the files of /_/, so that no relative or root path breaks behind the prefix.
func TestCharacterPageReferencesOnlyViewerAssets(t *testing.T) {
	s := newSite(t)
	s.upload("eu-brumamar-nandu")
	body := s.get(brumamar + "/").Body.String()
	refs := assetRef.FindAllStringSubmatch(body, -1)
	if len(refs) == 0 {
		t.Fatal("the page references no file")
	}
	for _, m := range refs {
		if !strings.HasPrefix(m[1], "/_/") {
			t.Errorf("the page references %q, want a /_/ path", m[1])
		}
		path := strings.TrimPrefix(m[1], "/_/")
		if strings.HasPrefix(path, "map/") {
			continue
		}
		if rec := s.get(m[1]); rec.Code != http.StatusOK {
			t.Errorf("GET %s = %d", m[1], rec.Code)
		}
	}
	if strings.Contains(body, " style=") || strings.Contains(strings.ToLower(body), "<script>") {
		t.Errorf("the page has an inline style attribute or script, which the policy blocks")
	}
}

func TestViewerAssetsAreOutsideTheRateLimit(t *testing.T) {
	s := newSiteWith(t, map[string]string{"MEMORIES_RATE_PUBLIC_PER_MINUTE": "4"})
	s.upload("eu-brumamar-nandu")
	// The register and the upload used the limit of another address, so the address below starts with a full window.
	get := func(path string) int {
		req := httptest.NewRequest("GET", path, nil)
		req.RemoteAddr = "192.0.2.9:1"
		rec := httptest.NewRecorder()
		s.public.ServeHTTP(rec, req)
		return rec.Code
	}
	for i := range 20 {
		if code := get("/_/style.css"); code != http.StatusOK {
			t.Fatalf("request %d to /_/style.css = %d, want 200", i, code)
		}
	}
	if code := get("/_/map/tiles/99/0_0.webp"); code != http.StatusNotFound {
		t.Errorf("a missing tile = %d, want 404 and not 429", code)
	}
	var got []int
	for range 5 {
		got = append(got, get(brumamar+"/"))
	}
	if want := []int{200, 200, 200, 200, 429}; !slices.Equal(got, want) {
		t.Errorf("character page statuses = %v, want %v", got, want)
	}
}

func TestRunNeedsTheViewerFolder(t *testing.T) {
	cfg := loadConfig(t, map[string]string{
		"MEMORIES_WEB_DIR":     t.TempDir(),
		"MEMORIES_PUBLIC_ADDR": freeAddr(t),
		"MEMORIES_ADMIN_ADDR":  freeAddr(t),
	})
	err := Run(t.Context(), cfg, quietLog())
	if err == nil || !strings.Contains(err.Error(), "MEMORIES_WEB_DIR") {
		t.Errorf("Run = %v, want an error that names MEMORIES_WEB_DIR", err)
	}
}

func TestOtherPagesKeepTheStrictPolicy(t *testing.T) {
	s := newSite(t)
	s.upload("eu-brumamar-nandu")
	for _, path := range []string{"/", "/nothing", brumamar + "/data/journey.jsonl", brumamar + "/data/entry.json", "/_/app.mjs", "/_/style.css", "/robots.txt", brumamar} {
		checkSecurityHeaders(t, s.get(path), path)
	}
	if rec := s.get(brumamar + "/"); rec.Header().Get("Content-Security-Policy") != characterPageCSP {
		t.Errorf("character page policy = %q", rec.Header().Get("Content-Security-Policy"))
	}
}
