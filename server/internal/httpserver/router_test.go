package httpserver

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/fmartingr/wow-addon-memories/server/internal/config"
	"github.com/fmartingr/wow-addon-memories/server/internal/site"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

const unlistedLine = "A character page is unlisted: anybody with the link can open it, and nobody can find it on this site."

var securityHeaders = map[string]string{
	"X-Content-Type-Options": "nosniff",
	"Referrer-Policy":        "no-referrer",
	"X-Frame-Options":        "DENY",
	"Content-Security-Policy": "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; " +
		"frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
}

// loadConfig loads env over the defaults, with the data folder in the temporary folder of the test.
func loadConfig(t *testing.T, env map[string]string) config.Config {
	t.Helper()
	dir := t.TempDir()
	cfg, err := config.Load(func(k string) string {
		if v, ok := env[k]; ok {
			return v
		}
		if k == "MEMORIES_DATA_DIR" {
			return dir
		}
		return ""
	})
	if err != nil {
		t.Fatal(err)
	}
	return cfg
}

func newHandlers(t *testing.T, cfg config.Config, logs io.Writer) (public, admin http.Handler) {
	t.Helper()
	s, err := site.New(siteOptions(cfg))
	if err != nil {
		t.Fatal(err)
	}
	st, err := store.Open(filepath.Join(cfg.DataDir, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	log := slog.New(slog.NewJSONHandler(logs, nil))
	return NewPublic(cfg, s, st, log), NewAdmin(s, log)
}

func do(h http.Handler, method, target string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, target, nil))
	return rec
}

func checkSecurityHeaders(t *testing.T, rec *httptest.ResponseRecorder, what string) {
	t.Helper()
	for name, want := range securityHeaders {
		if got := rec.Header().Get(name); got != want {
			t.Errorf("%s: %s = %q, want %q", what, name, got, want)
		}
	}
}

func TestHome(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, nil), io.Discard)
	rec := do(public, http.MethodGet, "/")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	body := rec.Body.String()
	for _, want := range []string{
		unlistedLine,
		`href="https://github.com/fmartingr/wow-addon-memories/releases/latest"`,
		`href="https://github.com/fmartingr/wow-addon-memories"`,
		"Memories_Combat", "Memories_Gathering", "Memories_Character", "Memories_Economy", "Memories_Social",
		"WoW Journey",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("home page lacks %q", want)
		}
	}
	for _, a := range site.Addons {
		if !strings.Contains(body, "<code>"+a.Name+"</code>") {
			t.Errorf("home page lacks the addon %s", a.Name)
		}
	}
	if got := rec.Header().Get("X-Robots-Tag"); got != "" {
		t.Errorf("X-Robots-Tag = %q, want none on the home page", got)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("Content-Type = %q", ct)
	}
	checkSecurityHeaders(t, rec, "home")
	for _, bad := range []string{"<script", "style=", "<img", "<iframe"} {
		if strings.Contains(body, bad) {
			t.Errorf("home page has %q, which the content security policy blocks", bad)
		}
	}
}

func TestHomeUploadStepsFollowTheRegistrationMode(t *testing.T) {
	for mode, wantInvite := range map[string]bool{config.RegistrationInvite: true, config.RegistrationOpen: false} {
		public, _ := newHandlers(t, loadConfig(t, map[string]string{"MEMORIES_REGISTRATION": mode}), io.Discard)
		body := do(public, http.MethodGet, "/").Body.String()
		if got := strings.Contains(body, "invite code"); got != wantInvite {
			t.Errorf("%s: home page mentions an invite code = %v, want %v", mode, got, wantInvite)
		}
	}
}

func TestHomeUsesConfiguredGitHubURL(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, map[string]string{
		"MEMORIES_GITHUB_URL": "https://github.com/me/fork/",
		"MEMORIES_SITE_NAME":  "Fork <Journey>",
	}), io.Discard)
	body := do(public, http.MethodGet, "/").Body.String()
	if !strings.Contains(body, `href="https://github.com/me/fork/releases/latest"`) || !strings.Contains(body, `href="https://github.com/me/fork"`) {
		t.Error("home page does not use the configured GitHub URL")
	}
	if !strings.Contains(body, "Fork &lt;Journey&gt;") || strings.Contains(body, "<Journey>") {
		t.Error("the site name is not HTML-escaped")
	}
}

func TestHomeWithoutGitHubURL(t *testing.T) {
	s, err := site.New(site.Options{Name: "X"})
	if err != nil {
		t.Fatal(err)
	}
	cfg := loadConfig(t, nil)
	st, err := store.Open(filepath.Join(cfg.DataDir, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	rec := do(NewPublic(cfg, s, st, slog.New(slog.NewJSONHandler(io.Discard, nil))), http.MethodGet, "/")
	body := rec.Body.String()
	if rec.Code != http.StatusOK || strings.Contains(body, "releases/latest") || strings.Contains(body, `href="">`) {
		t.Errorf("status %d; an empty GitHub URL must leave out the links", rec.Code)
	}
	if !strings.Contains(body, unlistedLine) {
		t.Error("home page lacks the unlisted line")
	}
}

func TestHeadRequests(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, nil), io.Discard)
	srv := httptest.NewServer(public)
	defer srv.Close()
	for _, path := range []string{"/", "/robots.txt", "/api/v1/info", "/nothing"} {
		get, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		getBody, _ := io.ReadAll(get.Body)
		get.Body.Close()
		head, err := http.Head(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		headBody, _ := io.ReadAll(head.Body)
		head.Body.Close()
		if head.StatusCode != get.StatusCode {
			t.Errorf("HEAD %s = %d, GET = %d", path, head.StatusCode, get.StatusCode)
		}
		if len(headBody) != 0 {
			t.Errorf("HEAD %s sent a body of %d bytes", path, len(headBody))
		}
		if head.ContentLength != int64(len(getBody)) {
			t.Errorf("HEAD %s Content-Length = %d, want %d", path, head.ContentLength, len(getBody))
		}
		for name, want := range securityHeaders {
			if got := head.Header.Get(name); got != want {
				t.Errorf("HEAD %s: %s = %q, want %q", path, name, got, want)
			}
		}
	}
}

func TestRobots(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, nil), io.Discard)
	rec := do(public, http.MethodGet, "/robots.txt")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if got, want := rec.Body.String(), "User-agent: *\nAllow: /$\nDisallow: /\n"; got != want {
		t.Errorf("robots.txt = %q, want %q", got, want)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Errorf("Content-Type = %q", ct)
	}
	checkSecurityHeaders(t, rec, "robots")
}

func TestInfo(t *testing.T) {
	for _, mode := range []string{"invite", "open"} {
		t.Run(mode, func(t *testing.T) {
			public, _ := newHandlers(t, loadConfig(t, map[string]string{
				"MEMORIES_REGISTRATION": mode,
				"MEMORIES_SITE_NAME":    "Friends Journey",
			}), io.Discard)
			rec := do(public, http.MethodGet, "/api/v1/info")
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d", rec.Code)
			}
			if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
				t.Errorf("Content-Type = %q", ct)
			}
			var got map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatal(err)
			}
			want := map[string]any{"api": float64(1), "name": "Friends Journey", "registration": mode}
			if len(got) != len(want) {
				t.Errorf("info = %v, want %v", got, want)
			}
			for k, v := range want {
				if got[k] != v {
					t.Errorf("info[%s] = %v, want %v", k, got[k], v)
				}
			}
			checkSecurityHeaders(t, rec, "info")
		})
	}
}

func TestUnknownPathsGiveTheSameNotFoundPage(t *testing.T) {
	public, admin := newHandlers(t, loadConfig(t, nil), io.Discard)
	paths := []string{
		"/nothing", "/index.html", "/wow/eu/brumamar/nandu/", "/app.js", "/data/memories.db",
		"/robots.txt/", "/assets/", "/%2e%2e/etc/passwd",
	}
	var first string
	for _, path := range paths {
		rec := do(public, http.MethodGet, path)
		if rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", path, rec.Code)
			continue
		}
		if !strings.Contains(rec.Body.String(), "Page not found") {
			t.Errorf("GET %s did not give the 404 page", path)
		}
		if first == "" {
			first = rec.Body.String()
		} else if rec.Body.String() != first {
			t.Errorf("GET %s gave a different 404 page", path)
		}
		checkSecurityHeaders(t, rec, "404 "+path)
	}
	post := do(public, http.MethodPost, "/")
	if post.Code != http.StatusNotFound {
		t.Errorf("POST / = %d, want 404", post.Code)
	}
	adminRec := do(admin, http.MethodGet, "/")
	if adminRec.Code != http.StatusNotFound || adminRec.Body.String() != first {
		t.Errorf("admin / = %d, want the generic 404 page", adminRec.Code)
	}
	checkSecurityHeaders(t, adminRec, "admin")
}

func TestDotDotPathsNeverServeFiles(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, nil), io.Discard)
	rec := do(public, http.MethodGet, "/assets/../../etc/passwd")
	if rec.Code < 300 || rec.Code > 399 {
		t.Fatalf("status = %d, want a redirect to the cleaned path", rec.Code)
	}
	loc := rec.Header().Get("Location")
	if loc != "/etc/passwd" {
		t.Fatalf("Location = %q", loc)
	}
	checkSecurityHeaders(t, rec, "redirect")
	if next := do(public, http.MethodGet, loc); next.Code != http.StatusNotFound {
		t.Errorf("GET %s = %d, want 404", loc, next.Code)
	}
}

func TestUnknownAPIPathGivesJSON(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, nil), io.Discard)
	rec := do(public, http.MethodGet, "/api/v1/nothing")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d", rec.Code)
	}
	var got map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("body is not JSON: %v", err)
	}
	if got["error"] != "not_found" || got["message"] == "" {
		t.Errorf("body = %v", got)
	}
	checkSecurityHeaders(t, rec, "api 404")
}

func TestWrongMethodGivesTheNotFoundPage(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, nil), io.Discard)
	rec := do(public, http.MethodPost, "/robots.txt")
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "Page not found") {
		t.Fatalf("status = %d, want the 404 page", rec.Code)
	}
	checkSecurityHeaders(t, rec, "POST robots.txt")
}

func TestStyleSheet(t *testing.T) {
	public, _ := newHandlers(t, loadConfig(t, nil), io.Discard)
	rec := do(public, http.MethodGet, site.CSSPath)
	if rec.Code != http.StatusOK || !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/css") {
		t.Fatalf("status %d, type %q", rec.Code, rec.Header().Get("Content-Type"))
	}
	if strings.Contains(rec.Body.String(), "http://") || strings.Contains(rec.Body.String(), "https://") || strings.Contains(rec.Body.String(), "@import") {
		t.Error("the style sheet loads an external resource")
	}
	checkSecurityHeaders(t, rec, "css")
}

func TestLogsHoldNoQueryAndNoMemoriesHeader(t *testing.T) {
	var logs bytes.Buffer
	public, _ := newHandlers(t, loadConfig(t, nil), &logs)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/info?secret=abc", nil)
	req.Header.Set("Memories-Signature", "sig-value")
	req.Header.Set("Memories-Key", "key-value")
	public.ServeHTTP(httptest.NewRecorder(), req)
	out := logs.String()
	if !strings.Contains(out, `"path":"/api/v1/info"`) || !strings.Contains(out, `"status":200`) {
		t.Errorf("log lacks the request: %s", out)
	}
	for _, leak := range []string{"secret=abc", "sig-value", "key-value"} {
		if strings.Contains(out, leak) {
			t.Errorf("log holds %q: %s", leak, out)
		}
	}
}
