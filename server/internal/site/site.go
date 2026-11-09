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
	// OpenRegistration drops the invite code step from the upload steps.
	OpenRegistration bool
}

// Addon is one row of the addon table.
type Addon struct {
	Name    string
	Records string
}

// Addons lists the 6 addons of the set, as the table of README.md does.
var Addons = []Addon{
	{"Memories", "Sessions, the position trail, progress (levels, XP, quests, discoveries, rest), deaths, close calls, travel (zones, flights, boats, hearthstone, summons, portals, mounts), dungeons and bosses, screenshots, and lines from other addons. This is the core addon and it is always on."},
	{"Memories_Combat", "Kills, rare kills and long fights."},
	{"Memories_Gathering", "Gathering, fishing, opening containers and chests, and pick pocket."},
	{"Memories_Character", "Skills, spells, recipes, talents, consumables, tamed pets, reputation, accepted quests, homes, flight paths and books."},
	{"Memories_Economy", "Loot, group rolls, gear, equipped items, money, trainers, the auction house, mail and trade."},
	{"Memories_Social", "Group members, your guild, enemy players, PvP kills and deaths, honor, duels, battlegrounds and PvP rank."},
}

type pageData struct {
	Name             string
	CSS              string
	BaseCSS          string
	GitHubURL        string
	ReleasesURL      string
	OpenRegistration bool
	Addons           []Addon
}

// Site holds the pages, rendered once at start.
type Site struct {
	home     []byte
	notFound []byte
}

// New renders the home page and the 404 page.
func New(opt Options) (*Site, error) {
	tpl, err := template.ParseFS(templateFS, "templates/*.html")
	if err != nil {
		return nil, fmt.Errorf("parse the page templates: %w", err)
	}
	data := pageData{Name: opt.Name, CSS: CSSPath, BaseCSS: BaseCSSPath, GitHubURL: opt.GitHubURL, OpenRegistration: opt.OpenRegistration, Addons: Addons}
	if opt.GitHubURL != "" {
		data.ReleasesURL = opt.GitHubURL + "/releases/latest"
	}
	s := &Site{}
	for name, dst := range map[string]*[]byte{"home.html": &s.home, "notfound.html": &s.notFound} {
		var buf bytes.Buffer
		if err := tpl.ExecuteTemplate(&buf, name, data); err != nil {
			return nil, fmt.Errorf("render %s: %w", name, err)
		}
		*dst = buf.Bytes()
	}
	return s, nil
}

// Home serves the home page.
func (s *Site) Home() http.Handler {
	return static(http.StatusOK, "text/html; charset=utf-8", "", s.home)
}

// NotFound serves the generic 404 page. An unknown path and a deleted character give the same page.
func (s *Site) NotFound() http.Handler {
	return static(http.StatusNotFound, "text/html; charset=utf-8", "", s.notFound)
}

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
