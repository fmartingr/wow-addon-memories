// Package site renders the static public pages and sets the security headers on every response.
package site

import (
	"bytes"
	"embed"
	"fmt"
	"html/template"
	"net/http"
	"strconv"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed static/site.css
var siteCSS []byte

// CSSPath is the URL of the layout style sheet of the home page and the 404 page. BaseCSSPath is the shared style
// sheet of the viewer folder (tokens, fonts and components), which the character page loads as well.
const (
	CSSPath     = "/assets/site.css"
	BaseCSSPath = AssetPrefix + "base.css"
)

// Options holds what the pages show.
type Options struct {
	Name      string
	GitHubURL string
	// CurseForgeURL is the page of the addons on CurseForge, and ExampleURL a character page to show as an example.
	// The home page leaves out a link with no address.
	CurseForgeURL string
	ExampleURL    string
	// OpenRegistration drops the invite code step from the upload steps.
	OpenRegistration bool
}

// Addon is one row of the addon table. The home page shows T(lang, "addon."+Name) as what it records.
type Addon struct {
	Name string
}

// Addons lists the 6 addons of the set, as the table of README.md does.
var Addons = []Addon{
	{"Memories"}, {"Memories_Combat"}, {"Memories_Gathering"}, {"Memories_Character"}, {"Memories_Economy"},
	{"Memories_Social"},
}

// LangLink is one link of the language picker.
type LangLink struct {
	Code    Lang
	Name    string
	Current bool
}

type pageData struct {
	Name             string
	Lang             Lang
	CSS              string
	BaseCSS          string
	GitHubURL        string
	ReleasesURL      string
	CurseForgeURL    string
	ExampleURL       string
	OpenRegistration bool
	Addons           []Addon
	Langs            []LangLink
}

// Site holds the pages, rendered once at start for each language.
type Site struct {
	home     map[Lang][]byte
	notFound map[Lang][]byte
}

// New renders the home page and the 404 page in each language.
func New(opt Options) (*Site, error) {
	base, err := template.New("").Funcs(langFuncs(Langs[0])).ParseFS(templateFS, "templates/*.html")
	if err != nil {
		return nil, fmt.Errorf("parse the page templates: %w", err)
	}
	s := &Site{home: map[Lang][]byte{}, notFound: map[Lang][]byte{}}
	for _, l := range Langs {
		tpl, err := base.Clone()
		if err != nil {
			return nil, fmt.Errorf("copy the page templates: %w", err)
		}
		tpl.Funcs(langFuncs(l))
		data := pageData{Name: opt.Name, Lang: l, CSS: CSSPath, BaseCSS: BaseCSSPath, GitHubURL: opt.GitHubURL, CurseForgeURL: opt.CurseForgeURL, ExampleURL: opt.ExampleURL, OpenRegistration: opt.OpenRegistration, Addons: Addons}
		for _, other := range Langs {
			data.Langs = append(data.Langs, LangLink{Code: other, Name: LangNames[other], Current: other == l})
		}
		if opt.GitHubURL != "" {
			data.ReleasesURL = opt.GitHubURL + "/releases/latest"
		}
		for name, dst := range map[string]map[Lang][]byte{"home.html": s.home, "notfound.html": s.notFound} {
			var buf bytes.Buffer
			if err := tpl.ExecuteTemplate(&buf, name, data); err != nil {
				return nil, fmt.Errorf("render %s in %s: %w", name, l, err)
			}
			dst[l] = buf.Bytes()
		}
	}
	return s, nil
}

// langFuncs gives the templates the text of l: T escapes it, H writes trusted markup.
func langFuncs(l Lang) template.FuncMap {
	return template.FuncMap{
		"T": func(key string) string { return T(l, key) },
		// The catalog is source code, so its markup is trusted.
		"H": func(key string) template.HTML { return template.HTML(T(l, key)) },
	}
}

// Home serves the home page in the language of the request.
func (s *Site) Home() http.Handler { return localized(http.StatusOK, s.home) }

// NotFound serves the generic 404 page in the language of the request. An unknown path and a deleted character give
// the same page.
func (s *Site) NotFound() http.Handler { return localized(http.StatusNotFound, s.notFound) }

// localized serves the page bytes of the language that Pick chooses. The answer depends on the cookie and on
// Accept-Language, so shared caches must keep a copy for each value.
func localized(status int, pages map[Lang][]byte) http.Handler {
	handlers := make(map[Lang]http.Handler, len(pages))
	for l, b := range pages {
		handlers[l] = static(status, "text/html; charset=utf-8", "", b)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l, _ := Pick(r)
		h := w.Header()
		h.Set("Content-Language", string(l))
		h.Set("Vary", varyLang)
		handlers[l].ServeHTTP(w, r)
	})
}

const varyLang = "Cookie, Accept-Language"

// Robots serves robots.txt: crawlers may read the home page only.
func (s *Site) Robots() http.Handler {
	return static(http.StatusOK, "text/plain; charset=utf-8", "", []byte("User-agent: *\nAllow: /$\nDisallow: /\n"))
}

// CSS serves the embedded style sheet.
func (s *Site) CSS() http.Handler {
	return static(http.StatusOK, "text/css; charset=utf-8", "public, max-age=3600", siteCSS)
}

// static serves fixed bytes. A HEAD request gets the headers only.
func static(status int, contentType, cacheControl string, body []byte) http.Handler {
	length := strconv.Itoa(len(body))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Type", contentType)
		h.Set("Content-Length", length)
		if cacheControl != "" {
			h.Set("Cache-Control", cacheControl)
		}
		w.WriteHeader(status)
		if r.Method != http.MethodHead {
			w.Write(body)
		}
	})
}
