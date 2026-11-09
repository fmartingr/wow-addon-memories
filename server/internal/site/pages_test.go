package site

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

const testIndex = `<!doctype html>
<html><head><title>Memories Viewer</title><link rel="stylesheet" href="/_/style.css"></head>
<BODY class="x"><main></main><script src="/_/app.js"></script></BODY></html>`

const shot = "WoWScrnShot_110126_114820.jpg"

type rig struct {
	t      *testing.T
	pages  *Pages
	st     *store.Store
	blobs  *store.DiskBlobs
	logs   *bytes.Buffer
	webDir string
}

func writeWeb(t *testing.T, index string) string {
	t.Helper()
	dir := t.TempDir()
	for name, body := range map[string]string{
		"index.html": index, "app.mjs": "export {}", "lib/format.mjs": "export const x = 1", "kinds.js": "window.KINDS={}",
		"style.css": "body{}", "icon.png": "png", "test/a.test.mjs": "x", "map/world.js": "window.WORLD={}",
		"fonts/a.woff2": "font", ".hidden.js": "x",
	} {
		file := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(file), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func newRig(t *testing.T) *rig {
	t.Helper()
	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	blobs, err := store.NewDiskBlobs(dir)
	if err != nil {
		t.Fatal(err)
	}
	site, err := New(Options{Name: "X"})
	if err != nil {
		t.Fatal(err)
	}
	r := &rig{t: t, st: st, blobs: blobs, logs: &bytes.Buffer{}, webDir: writeWeb(t, testIndex)}
	r.pages, err = NewPages(r.webDir, st, blobs, site.NotFound(), slog.New(slog.NewJSONHandler(r.logs, nil)))
	if err != nil {
		t.Fatal(err)
	}
	return r
}

// claim makes the claim of wow/eu/brumamar/nandu and returns its id.
func (r *rig) claim() int64 {
	r.t.Helper()
	pub := bytes.Repeat([]byte{1}, 32)
	if _, err := r.st.Register(context.Background(), store.RegisterInput{Public: pub, Nonce: pub[:16]}); err != nil {
		r.t.Fatal(err)
	}
	key, err := r.st.KeyByPublic(context.Background(), pub)
	if err != nil {
		r.t.Fatal(err)
	}
	id, err := r.st.CreateClaim(context.Background(), store.Claim{
		Flavor: "wow", Region: "eu", Realm: "brumamar", Name: "nandu", GUID: "g", KeyID: key.ID,
	})
	if err != nil {
		r.t.Fatal(err)
	}
	return id
}

func (r *rig) write(id int64, name, body string) {
	r.t.Helper()
	if err := r.blobs.Write(context.Background(), strconv.FormatInt(id, 10)+"/"+name, strings.NewReader(body)); err != nil {
		r.t.Fatal(err)
	}
}

func (r *rig) get(method, target string, hdr ...string) *httptest.ResponseRecorder {
	mux := http.NewServeMux()
	r.pages.Routes(mux)
	req := httptest.NewRequest(method, target, nil)
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

const base = "/wow/eu/brumamar/nandu"

func isNotFound(rec *httptest.ResponseRecorder) bool {
	return rec.Code == http.StatusNotFound && strings.Contains(rec.Body.String(), "Page not found")
}

func TestNewPagesNeedsTheViewerFiles(t *testing.T) {
	site, _ := New(Options{})
	for name, tc := range map[string]struct {
		dir  func() string
		want string
	}{
		"no folder":  {func() string { return filepath.Join(t.TempDir(), "none") }, "index.html"},
		"no body":    {func() string { return writeWeb(t, "<html><head><title>x</title></head></html>") }, "<title>"},
		"no title":   {func() string { return writeWeb(t, "<html><body></body></html>") }, "<title>"},
		"title last": {func() string { return writeWeb(t, "<body></body><title>x</title>") }, "<title>"},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := NewPages(tc.dir(), nil, nil, site.NotFound(), slog.Default())
			if err == nil || !strings.Contains(err.Error(), tc.want) || !strings.Contains(err.Error(), "MEMORIES_WEB_DIR") {
				t.Errorf("err = %v, want a message with %q and the setting", err, tc.want)
			}
		})
	}
}

// getAssets serves the /_/ files of the rig through Assets, as the public router does.
func (r *rig) getAssets(method, target string, hdr ...string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, target, nil)
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	rec := httptest.NewRecorder()
	r.pages.Assets().ServeHTTP(rec, req)
	return rec
}

func TestViewerFilesAreServedUnderTheUnderscorePrefix(t *testing.T) {
	r := newRig(t)
	for path, want := range map[string]struct{ body, ct string }{
		"/_/app.mjs":        {"export {}", "text/javascript"},
		"/_/lib/format.mjs": {"export const x = 1", "text/javascript"},
		"/_/kinds.js":       {"window.KINDS={}", "text/javascript"},
		"/_/style.css":      {"body{}", "text/css"},
		"/_/icon.png":       {"png", "image/png"},
	} {
		rec := r.getAssets("GET", path)
		if rec.Code != 200 || rec.Body.String() != want.body || !strings.HasPrefix(rec.Header().Get("Content-Type"), want.ct) {
			t.Errorf("%s: %d %q %q", path, rec.Code, rec.Header().Get("Content-Type"), rec.Body)
		}
		etag := rec.Header().Get("ETag")
		if etag == "" || rec.Header().Get("Cache-Control") != "no-cache" {
			t.Errorf("%s: ETag %q, Cache-Control %q", path, etag, rec.Header().Get("Cache-Control"))
		}
		if again := r.getAssets("GET", path, "If-None-Match", etag); again.Code != http.StatusNotModified {
			t.Errorf("%s with its ETag = %d, want 304", path, again.Code)
		}
	}
	for _, path := range []string{"/_/test/a.test.mjs", "/_/map/world.js.", "/_/.hidden.js", "/_/index.html", "/_/", "/_/nothing.js"} {
		if rec := r.getAssets("GET", path); rec.Code != http.StatusNotFound || strings.Contains(rec.Body.String(), "export") {
			t.Errorf("GET %s = %d, want 404", path, rec.Code)
		}
	}
	for _, path := range []string{"/app.js", "/style.css", "/kinds.js", "/index.html"} {
		if rec := r.get("GET", path); !isNotFound(rec) {
			t.Errorf("GET %s = %d, want the 404 page: the viewer files are under /_/ only", path, rec.Code)
		}
	}
	if rec := r.getAssets("POST", "/_/app.mjs"); rec.Code == 200 || rec.Body.String() == "export {}" {
		t.Errorf("POST /_/app.mjs = %d, want no file", rec.Code)
	}
	head := r.getAssets("HEAD", "/_/style.css")
	if head.Code != 200 || head.Body.Len() != 0 {
		t.Errorf("HEAD: %d, %d body bytes", head.Code, head.Body.Len())
	}
}

func TestViewerFilesComeFromMapAndFontsFolders(t *testing.T) {
	r := newRig(t)
	rec := r.getAssets("GET", "/_/map/world.js")
	if rec.Code != 200 || rec.Body.String() != "window.WORLD={}" || rec.Header().Get("Cache-Control") != "public, max-age=86400" {
		t.Errorf("map/world.js: %d %q %q", rec.Code, rec.Body, rec.Header())
	}
	rec = r.getAssets("GET", "/_/fonts/a.woff2")
	if rec.Code != 200 || rec.Header().Get("Content-Type") != "font/woff2" {
		t.Errorf("fonts/a.woff2: %d %q", rec.Code, rec.Header().Get("Content-Type"))
	}
}

func TestNewPagesRejectsAViewerTreeAbove8MiB(t *testing.T) {
	site, _ := New(Options{})
	dir := writeWeb(t, testIndex)
	if err := os.WriteFile(filepath.Join(dir, "big.js"), make([]byte, maxViewerBytes+1), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := NewPages(dir, nil, nil, site.NotFound(), slog.Default())
	if err == nil || !strings.Contains(err.Error(), "8 MiB") || !strings.Contains(err.Error(), "MEMORIES_WEB_DIR") {
		t.Errorf("err = %v, want a message about 8 MiB and the setting", err)
	}
	if err := os.Remove(filepath.Join(dir, "big.js")); err != nil {
		t.Fatal(err)
	}
	// The map and fonts folders are not in memory, so large art does not count.
	if err := os.WriteFile(filepath.Join(dir, "map", "big.js"), make([]byte, maxViewerBytes+1), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := NewPages(dir, nil, nil, site.NotFound(), slog.Default()); err != nil {
		t.Errorf("a large file in map/ gave %v, want none", err)
	}
}

func TestCharacterPageAllowsOnlyTheWowheadHosts(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `{"name":"Ñandú"}`)
	want := "default-src 'self'; img-src 'self' data: https://wow.zamimg.com; " +
		"script-src 'self' https://wow.zamimg.com https://nether.wowhead.com; style-src 'self' https://wow.zamimg.com; " +
		"connect-src 'self' https://nether.wowhead.com; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
	if got := r.get("GET", base+"/").Header().Get("Content-Security-Policy"); got != want {
		t.Errorf("policy = %q, want %q", got, want)
	}
	if strings.Contains(want, "unsafe-inline") || strings.Contains(want, "*") {
		t.Errorf("the policy is wider than the Wowhead hosts")
	}
	if got := r.get("GET", base+"/data/entry.json").Header().Get("Content-Security-Policy"); got != "" {
		t.Errorf("a data file sets its own policy %q, want the base policy from Headers", got)
	}
}

func TestCharacterPageSetsTheEntryAndTheTitle(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `{"name":"Ñandú <b>","realm":"brumamar","realmLabel":"Bruma & Mar"}`)
	rec := r.get("GET", base+"/")
	body := rec.Body.String()
	if rec.Code != 200 {
		t.Fatalf("status %d", rec.Code)
	}
	for _, want := range []string{
		"<title>Ñandú &lt;b&gt; — Bruma &amp; Mar — Memories</title>",
		`<BODY data-entry="data/entry.json" class="x">`,
		`<link rel="stylesheet" href="/_/style.css">`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("page lacks %q:\n%s", want, body)
		}
	}
	if strings.Contains(body, "Memories Viewer") || strings.Contains(body, "<b>") {
		t.Errorf("page keeps the template title or an unescaped name:\n%s", body)
	}
	h := rec.Header()
	if h.Get("X-Robots-Tag") != "noindex, nofollow" || h.Get("Cache-Control") != "no-cache" || h.Get("ETag") == "" ||
		!strings.HasPrefix(h.Get("Content-Type"), "text/html") {
		t.Errorf("headers: %v", h)
	}
	if again := r.get("GET", base+"/", "If-None-Match", h.Get("ETag")); again.Code != http.StatusNotModified {
		t.Errorf("page with its ETag = %d, want 304", again.Code)
	}
	head := r.get("HEAD", base+"/")
	if head.Code != 200 || head.Body.Len() != 0 || head.Header().Get("Content-Length") != strconv.Itoa(len(body)) {
		t.Errorf("HEAD: %d, %d body bytes, length %q", head.Code, head.Body.Len(), head.Header().Get("Content-Length"))
	}
}

func TestPageTitleFallsBackToThePathNames(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `not json`)
	if rec := r.get("GET", base+"/"); rec.Code != 200 || !strings.Contains(rec.Body.String(), "<title>nandu — brumamar — Memories</title>") {
		t.Errorf("damaged file: %d %s", rec.Code, rec.Body)
	}
	r.write(id, "character.json", `{"name":"Nandu","realm":"Bruma Mar"}`)
	if rec := r.get("GET", base+"/"); !strings.Contains(rec.Body.String(), "<title>Nandu — Bruma Mar — Memories</title>") {
		t.Errorf("no realm label: %s", rec.Body)
	}
}

func TestPathWithoutTheSlashRedirects(t *testing.T) {
	r := newRig(t)
	rec := r.get("GET", base)
	if rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != base+"/" {
		t.Errorf("status %d, Location %q", rec.Code, rec.Header().Get("Location"))
	}
	if rec.Header().Get("X-Robots-Tag") != "noindex, nofollow" {
		t.Error("the redirect lacks noindex")
	}
	if rec := r.get("GET", base+"?x=1"); rec.Header().Get("Location") != base+"/" {
		t.Errorf("Location with a query = %q", rec.Header().Get("Location"))
	}
}

func TestEveryOtherPathGivesTheNotFoundPage(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `{"name":"Nandu"}`)
	r.write(id, "journey.jsonl", "")
	var first string
	for _, path := range []string{
		"/", // handled by the router in production, here the catch-all
		"/wow", "/wow/eu", "/wow/eu/brumamar", "/wow/eu/brumamar/other/", "/wow/eu/brumamar/other/data/journey.jsonl",
		"/WOW/eu/brumamar/nandu/", "/wow/EU/brumamar/nandu/", "/wow/eu/Brumamar/nandu/", "/wow/eu/brumamar/Nandu/",
		base + "/index.html", base + "/data", base + "/data/", base + "/data/journey.jsonl/",
		base + "/data/memories.db", base + "/data/%2e%2e/memories.db", base + "/data/entry.json/x",
		base + "/data/trail.jsonl",                                                                  // a claim whose file does not exist
		base + "/data/screenshots", base + "/data/screenshots/", base + "/data/screenshots/" + shot, // not uploaded
		base + "/data/screenshots/x.jpg", base + "/data/screenshots/WoWScrnShot_110126_114820.tga",
		base + "/data/screenshots/WoWScrnShot_110126_114820.jpg/x",
		base + "/other/journey.jsonl", base + "/data/screenshots/a/b",
	} {
		rec := r.get("GET", path)
		if !isNotFound(rec) {
			t.Errorf("GET %s = %d, want the 404 page", path, rec.Code)
			continue
		}
		if first == "" {
			first = rec.Body.String()
		}
		if rec.Body.String() != first || rec.Header().Get("X-Robots-Tag") != "" {
			t.Errorf("GET %s gave another page or extra headers", path)
		}
	}
	for _, method := range []string{"POST", "PUT", "DELETE"} {
		if rec := r.get(method, base+"/"); !isNotFound(rec) {
			t.Errorf("%s = %d, want the 404 page", method, rec.Code)
		}
	}
}

func TestClaimWithoutFilesGivesTheNotFoundPage(t *testing.T) {
	r := newRig(t)
	r.claim()
	if rec := r.get("GET", base+"/"); !isNotFound(rec) {
		t.Errorf("page of a claim with no character.json = %d", rec.Code)
	}
}

func TestDataFilesAreStreamedWithTypesAndETags(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	files := map[string]struct{ body, ct string }{
		"entry.json":     {`{"id":"wow/eu/brumamar/nandu"}`, "application/json"},
		"character.json": {`{"name":"Nandu"}`, "application/json"},
		"journey.jsonl":  {"{\"k\":\"zo\"}\n", "application/x-ndjson"},
		"trail.jsonl":    {"", "application/x-ndjson"},
	}
	for name, f := range files {
		r.write(id, name, f.body)
	}
	r.write(id, "screenshots/"+shot, "JPEGBYTES")
	r.write(id, "screenshots/WoWScrnShot_110126_114821.png", "PNGBYTES")

	urls := map[string]struct{ body, ct string }{
		base + "/data/screenshots/" + shot:                       {"JPEGBYTES", "image/jpeg"},
		base + "/data/screenshots/WoWScrnShot_110126_114821.png": {"PNGBYTES", "image/png"},
	}
	for name, f := range files {
		urls[base+"/data/"+name] = f
	}
	for url, want := range urls {
		rec := r.get("GET", url)
		h := rec.Header()
		if rec.Code != 200 || rec.Body.String() != want.body || h.Get("Content-Type") != want.ct {
			t.Errorf("%s: %d %q %q", url, rec.Code, h.Get("Content-Type"), rec.Body)
		}
		etag := h.Get("ETag")
		if len(etag) != 66 || etag[0] != '"' || etag[65] != '"' {
			t.Errorf("%s: ETag %q is not a quoted hex SHA-256", url, etag)
		}
		if h.Get("X-Robots-Tag") != "noindex, nofollow" || h.Get("Cache-Control") != "no-cache" {
			t.Errorf("%s: headers %v", url, h)
		}
		again := r.get("GET", url, "If-None-Match", etag)
		if again.Code != http.StatusNotModified || again.Body.Len() != 0 || again.Header().Get("ETag") != etag {
			t.Errorf("%s with its ETag: %d %q", url, again.Code, again.Body)
		}
		if other := r.get("GET", url, "If-None-Match", `"nope"`); other.Code != 200 {
			t.Errorf("%s with another ETag = %d", url, other.Code)
		}
		head := r.get("HEAD", url)
		if head.Code != 200 || head.Body.Len() != 0 || head.Header().Get("ETag") != etag {
			t.Errorf("HEAD %s: %d, ETag %q", url, head.Code, head.Header().Get("ETag"))
		}
	}
	// The ETag follows a new version of the file.
	url := base + "/data/journey.jsonl"
	before := r.get("GET", url).Header().Get("ETag")
	r.write(id, "journey.jsonl", "{\"k\":\"zo\"}\n{\"k\":\"lv\"}\n")
	after := r.get("GET", url)
	if after.Header().Get("ETag") == before || !strings.Contains(after.Body.String(), `"lv"`) {
		t.Errorf("ETag %q -> %q after a new file", before, after.Header().Get("ETag"))
	}
	if stale := r.get("GET", url, "If-None-Match", before); stale.Code != 200 {
		t.Errorf("old ETag = %d, want 200", stale.Code)
	}
	if rng := r.get("GET", base+"/data/screenshots/"+shot, "Range", "bytes=0-3"); rng.Code != http.StatusPartialContent || rng.Body.String() != "JPEG" {
		t.Errorf("range: %d %q", rng.Code, rng.Body)
	}
}

func TestDataOfADeletedCharacterGivesTheNotFoundPage(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `{"name":"Nandu"}`)
	r.write(id, "entry.json", `{}`)
	for _, p := range []string{"/", "/data/entry.json"} {
		if rec := r.get("GET", base+p); rec.Code != 200 {
			t.Fatalf("%s = %d before the delete", p, rec.Code)
		}
	}
	if err := r.blobs.RemoveAll(context.Background(), strconv.FormatInt(id, 10)+"/"); err != nil {
		t.Fatal(err)
	}
	if err := r.st.DeleteClaim(context.Background(), id); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"/", "/data/entry.json"} {
		if rec := r.get("GET", base+p); !isNotFound(rec) {
			t.Errorf("%s = %d after the delete, want the 404 page", p, rec.Code)
		}
	}
}

type failingClaims struct{ err error }

func (f failingClaims) ClaimByPath(context.Context, string, string, string, string) (store.Claim, error) {
	return store.Claim{}, f.err
}

func TestStoreFailureGivesAPlainError(t *testing.T) {
	r := newRig(t)
	r.pages.claims = failingClaims{errors.New("disk I/O error: secret detail")}
	for _, p := range []string{"/", "/data/entry.json"} {
		rec := r.get("GET", base+p)
		if rec.Code != http.StatusInternalServerError || strings.Contains(rec.Body.String(), "secret") ||
			!strings.Contains(rec.Body.String(), "Try again") {
			t.Errorf("%s: %d %q", p, rec.Code, rec.Body)
		}
	}
	if !strings.Contains(r.logs.String(), "secret detail") {
		t.Error("the failure is not logged")
	}
}

type brokenBlobs struct {
	store.Blobs
	open func(string) (store.File, error)
}

func (b brokenBlobs) Open(ctx context.Context, p string) (store.File, error) {
	if f, err := b.open(p); f != nil || err != nil {
		return f, err
	}
	return b.Blobs.Open(ctx, p)
}

func TestBlobFailuresGiveAPlainError(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `{"name":"Nandu"}`)
	r.write(id, "journey.jsonl", "x")
	r.pages.blobs = brokenBlobs{r.blobs, func(string) (store.File, error) { return nil, errors.New("permission denied") }}
	for _, p := range []string{"/", "/data/journey.jsonl"} {
		if rec := r.get("GET", base+p); rec.Code != http.StatusInternalServerError {
			t.Errorf("%s = %d, want 500", p, rec.Code)
		}
	}
	r.pages.blobs = brokenBlobs{r.blobs, func(string) (store.File, error) { return badFile{}, nil }}
	if rec := r.get("GET", base+"/data/journey.jsonl"); rec.Code != http.StatusInternalServerError {
		t.Errorf("stat failure = %d, want 500", rec.Code)
	}
	r.pages.blobs = brokenBlobs{r.blobs, func(p string) (store.File, error) {
		if strings.HasSuffix(p, "journey.jsonl") {
			return unreadableFile{}, nil
		}
		return nil, nil
	}}
	if rec := r.get("GET", base+"/data/journey.jsonl"); rec.Code != http.StatusInternalServerError {
		t.Errorf("read failure = %d, want 500", rec.Code)
	}
}

type badFile struct{ store.File }

func (badFile) Stat() (os.FileInfo, error) { return nil, errors.New("stat failed") }
func (badFile) Close() error               { return nil }

type unreadableFile struct{ badFile }

func (unreadableFile) Stat() (os.FileInfo, error) { return os.Stat(os.DevNull) }
func (unreadableFile) Read([]byte) (int, error)   { return 0, errors.New("read failed") }

func TestETagCacheHashesOnceAndStaysBounded(t *testing.T) {
	c := etagCache{m: map[etagKey]string{}}
	f := bytes.NewReader([]byte("abc"))
	k := etagKey{claim: 1, file: "a", size: 3, mod: 1}
	first, err := c.of(k, f)
	if err != nil {
		t.Fatal(err)
	}
	if rest, _ := io.ReadAll(f); string(rest) != "abc" {
		t.Errorf("the reader was left at %q, want its start", rest)
	}
	// A cached key does not read the file again: an empty reader gives the same tag.
	if second, _ := c.of(k, bytes.NewReader(nil)); second != first {
		t.Errorf("cached tag %q, want %q", second, first)
	}
	for i := range maxCachedETags + 5 {
		c.of(etagKey{claim: int64(i + 10)}, bytes.NewReader(nil))
	}
	if len(c.m) > maxCachedETags {
		t.Errorf("the cache holds %d entries, the cap is %d", len(c.m), maxCachedETags)
	}
}
