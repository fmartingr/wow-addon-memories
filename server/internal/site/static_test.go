package site

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func staticRig(t *testing.T) (http.Handler, string) {
	t.Helper()
	dir := t.TempDir()
	root := filepath.Join(dir, "map")
	for name, body := range map[string]string{
		"tiles/0/0_0.webp": "tile", "world.js": "w", ".hidden.webp": "h", "tiles/0/note.txt": "n",
	} {
		file := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(file), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "store.db"), []byte("SECRET"), 0o600); err != nil {
		t.Fatal(err)
	}
	return NewStatic("/_/map/", root, MapTypes), dir
}

func serveStatic(h http.Handler, method, target string, hdr ...string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, target, nil)
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestStaticServesListedTypesWithCache(t *testing.T) {
	h, _ := staticRig(t)
	rec := serveStatic(h, "GET", "/_/map/tiles/0/0_0.webp")
	if rec.Code != 200 || rec.Body.String() != "tile" || rec.Header().Get("Content-Type") != "image/webp" ||
		rec.Header().Get("Cache-Control") != "public, max-age=86400" || rec.Header().Get("Last-Modified") == "" {
		t.Fatalf("%d %q %v", rec.Code, rec.Body, rec.Header())
	}
	later := time.Now().Add(time.Hour).UTC().Format(http.TimeFormat)
	if again := serveStatic(h, "GET", "/_/map/tiles/0/0_0.webp", "If-Modified-Since", later); again.Code != http.StatusNotModified {
		t.Errorf("If-Modified-Since = %d, want 304", again.Code)
	}
	if head := serveStatic(h, "HEAD", "/_/map/world.js"); head.Code != 200 || head.Body.Len() != 0 ||
		head.Header().Get("Content-Type") != "text/javascript; charset=utf-8" {
		t.Errorf("HEAD: %d %d %v", head.Code, head.Body.Len(), head.Header())
	}
}

func TestStaticRejectsTraversalFoldersAndUnlistedTypes(t *testing.T) {
	h, _ := staticRig(t)
	for _, target := range []string{
		"/_/map/../store.db", "/_/map/%2e%2e/store.db", "/_/map/..%2fstore.db", "/_/map/tiles/", "/_/map/tiles",
		"/_/map/", "/_/map/.hidden.webp", "/_/map/tiles/0/note.txt", "/_/map/tiles/0/0_0.WEBP.bak", "/_/map/tiles//0/0_0.webp",
		"/_/map/./world.js", "/other/world.js",
	} {
		rec := serveStatic(h, "GET", target)
		if rec.Code != http.StatusNotFound || strings.Contains(rec.Body.String(), "SECRET") || rec.Header().Get("Cache-Control") != "" ||
			rec.Header().Get("Content-Type") == "image/webp" {
			t.Errorf("GET %s = %d %q %v, want a plain 404", target, rec.Code, rec.Body, rec.Header())
		}
	}
	if rec := serveStatic(h, "POST", "/_/map/world.js"); rec.Code != http.StatusNotFound {
		t.Errorf("POST = %d, want 404", rec.Code)
	}
	if rec := serveStatic(h, "GET", "/_/map/missing.webp"); rec.Code != http.StatusNotFound || rec.Header().Get("Content-Type") == "image/webp" {
		t.Errorf("missing tile: %d %v", rec.Code, rec.Header())
	}
}

func TestStaticWithoutTheFolderGives404(t *testing.T) {
	h := NewStatic("/_/map/", filepath.Join(t.TempDir(), "none"), MapTypes)
	for _, target := range []string{"/_/map/world.js", "/_/map/tiles/0/0_0.webp"} {
		if rec := serveStatic(h, "GET", target); rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", target, rec.Code)
		}
	}
}

func TestStaticFontTypes(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.woff2"), []byte("f"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "x.ttf"), []byte("f"), 0o600); err != nil {
		t.Fatal(err)
	}
	h := NewStatic("/_/fonts/", dir, FontTypes)
	if rec := serveStatic(h, "GET", "/_/fonts/a.woff2"); rec.Code != 200 || rec.Header().Get("Content-Type") != "font/woff2" {
		t.Errorf("woff2: %d %v", rec.Code, rec.Header())
	}
	if rec := serveStatic(h, "GET", "/_/fonts/x.ttf"); rec.Code != http.StatusNotFound {
		t.Errorf("ttf: %d, want 404", rec.Code)
	}
}
