package site

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func serve(t *testing.T, h http.Handler, method string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, "/", nil))
	return rec
}

func newSite(t *testing.T, opt Options) *Site {
	t.Helper()
	s, err := New(opt)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestHomeShowsTheLinksAndTheUnlistedLine(t *testing.T) {
	s := newSite(t, Options{Name: "My Site", GitHubURL: "https://github.com/a/b"})
	rec := serve(t, s.Home(), http.MethodGet)
	body := rec.Body.String()
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	for _, want := range []string{
		"<title>My Site</title>",
		`href="https://github.com/a/b/releases/latest"`,
		`href="https://github.com/a/b"`,
		"A character page is unlisted: anybody with the link can open it, and nobody can find it on this site.",
		`href="` + CSSPath + `"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("home page lacks %q", want)
		}
	}
	if len(Addons) != 6 {
		t.Errorf("%d addons, want 6", len(Addons))
	}
}

func TestHomeLeavesOutTheLinksWithoutAGitHubURL(t *testing.T) {
	s := newSite(t, Options{Name: "My Site"})
	body := serve(t, s.Home(), http.MethodGet).Body.String()
	if strings.Contains(body, "github.com") || strings.Contains(body, "releases/latest") {
		t.Error("home page links to GitHub with no GitHub URL")
	}
}

func TestHomeEscapesTheName(t *testing.T) {
	s := newSite(t, Options{Name: `<script>alert(1)</script>`})
	body := serve(t, s.Home(), http.MethodGet).Body.String()
	if strings.Contains(body, "<script>") {
		t.Error("the site name is not escaped")
	}
}

func TestHeadHasNoBody(t *testing.T) {
	s := newSite(t, Options{Name: "X"})
	for name, h := range map[string]http.Handler{"home": s.Home(), "404": s.NotFound(), "robots": s.Robots(), "css": s.CSS()} {
		rec := serve(t, h, http.MethodHead)
		if rec.Body.Len() != 0 || rec.Header().Get("Content-Length") == "0" {
			t.Errorf("%s: body %d bytes, Content-Length %q", name, rec.Body.Len(), rec.Header().Get("Content-Length"))
		}
	}
}

func TestNotFoundPage(t *testing.T) {
	s := newSite(t, Options{Name: "X"})
	rec := serve(t, s.NotFound(), http.MethodGet)
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "Page not found") {
		t.Errorf("status %d body %q", rec.Code, rec.Body.String())
	}
	if !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/html") {
		t.Errorf("Content-Type = %q", rec.Header().Get("Content-Type"))
	}
}

func TestRobots(t *testing.T) {
	s := newSite(t, Options{Name: "X"})
	rec := serve(t, s.Robots(), http.MethodGet)
	if rec.Body.String() != "User-agent: *\nAllow: /$\nDisallow: /\n" {
		t.Errorf("robots.txt = %q", rec.Body.String())
	}
}

func TestCSS(t *testing.T) {
	s := newSite(t, Options{Name: "X"})
	rec := serve(t, s.CSS(), http.MethodGet)
	if rec.Code != http.StatusOK || rec.Body.Len() == 0 || !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/css") {
		t.Errorf("status %d, %d bytes, type %q", rec.Code, rec.Body.Len(), rec.Header().Get("Content-Type"))
	}
}
