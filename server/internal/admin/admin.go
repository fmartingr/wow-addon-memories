// Package admin is the admin page: plain HTML forms on a loopback port, with no JavaScript. The admin manages
// screenshot requests, keys, invites and characters from it. Every change is a POST with a CSRF token, followed by a
// redirect.
package admin

import (
	"crypto/rand"
	"crypto/subtle"
	"embed"
	"encoding/base64"
	"errors"
	"fmt"
	"html/template"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/characters"
	"github.com/fmartingr/wow-addon-memories/server/internal/ids"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed admin.css
var adminCSS []byte

const (
	csrfCookie  = "memories_admin_csrf"
	flashCookie = "memories_admin_flash"
	// maxForm bounds the body of a POST: the forms hold a few short fields.
	maxForm = 16 << 10
	// pageSize is the number of rows of one page of a list.
	pageSize = 25

	defaultInviteDays = 30
	maxInviteDays     = 365
	maxNoteRunes      = 100
	flashTTL          = 5 * time.Minute
	maxFlashes        = 64
)

// Options are what New needs.
type Options struct {
	// Addr is the listen address of the admin server. Its port is the only port that the Host check accepts.
	Addr string
	// SiteURL is the public address of the site, for the links to character pages.
	SiteURL  string
	Store    *store.Store
	Chars    *characters.Service
	NotFound http.Handler
	Log      *slog.Logger
}

// Admin serves the admin pages.
type Admin struct {
	opt   Options
	hosts map[string]bool
	pages map[string]*template.Template
	flash flashes
	now   func() time.Time
}

// New builds the admin handler. It warns in the log when the address is not a loopback address.
func New(opt Options) (*Admin, error) {
	_, port, err := net.SplitHostPort(opt.Addr)
	if err != nil {
		return nil, fmt.Errorf("the admin address %q is not a host:port address: %w", opt.Addr, err)
	}
	a := &Admin{
		opt:   opt,
		hosts: map[string]bool{"localhost:" + port: true, "127.0.0.1:" + port: true},
		flash: flashes{m: map[string]flash{}},
		now:   time.Now,
	}
	if a.pages, err = parseTemplates(); err != nil {
		return nil, err
	}
	if !isLoopback(opt.Addr) {
		opt.Log.Warn("the admin address is not a loopback address, so anybody who can reach it can manage the site. "+
			"Listen on 127.0.0.1 and reach the page through an SSH tunnel. Inside Docker, publish the port on 127.0.0.1 only",
			"addr", opt.Addr)
	}
	return a, nil
}

// isLoopback reports whether addr listens on a loopback address only. An empty or unspecified host listens everywhere.
func isLoopback(addr string) bool {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return false
	}
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// Handler returns the routes of the admin page.
func (a *Admin) Handler() http.Handler {
	mux := http.NewServeMux()
	notFound := a.opt.NotFound
	if notFound == nil {
		notFound = http.NotFoundHandler()
	}
	mux.Handle("/", notFound)
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/requests", http.StatusSeeOther)
	})
	mux.HandleFunc("GET /admin.css", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		w.Write(adminCSS)
	})
	mux.HandleFunc("GET /requests", a.page("requests", a.requestsPage))
	mux.HandleFunc("GET /keys", a.page("keys", a.keysPage))
	mux.HandleFunc("GET /invites", a.page("invites", a.invitesPage))
	mux.HandleFunc("GET /characters", a.page("characters", a.charactersPage))
	for pattern, h := range map[string]http.HandlerFunc{
		"/requests/approve":  a.approve,
		"/requests/deny":     a.deny,
		"/keys/revoke":       a.revokeKey,
		"/keys/screenshots":  a.revokeScreenshots,
		"/invites/create":    a.createInvite,
		"/invites/revoke":    a.revokeInvite,
		"/characters/delete": a.deleteCharacter,
		"/characters/move":   a.moveCharacter,
	} {
		mux.Handle("POST "+pattern, a.protect(h))
	}
	return a.guard(mux)
}

// guard rejects a request whose Host is not the loopback address and port of the admin server. This is what stops a
// DNS rebinding page: the browser sends the attacker's name as Host.
func (a *Admin) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !a.hosts[strings.ToLower(r.Host)] {
			forbid(w, "This address is not allowed. Open the admin page as http://127.0.0.1:"+a.port()+"/ or http://localhost:"+a.port()+"/.")
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		// With no-referrer, browsers send "Origin: null" on a form POST, which protect refuses. same-origin keeps the
		// real Origin on the admin's own forms and still sends nothing to another site.
		w.Header().Set("Referrer-Policy", "same-origin")
		next.ServeHTTP(w, r)
	})
}

func (a *Admin) port() string {
	_, port, _ := net.SplitHostPort(a.opt.Addr)
	return port
}

func forbid(w http.ResponseWriter, message string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusForbidden)
	fmt.Fprintln(w, message)
}

// protect checks the CSRF token and the Origin of a POST, then parses the form for the handler.
func (a *Admin) protect(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		const blocked = "The request was blocked because its security token is missing or wrong. Go back to the admin page, reload it and try again."
		if origin := r.Header.Get("Origin"); origin != "" {
			u, err := url.Parse(origin)
			if err != nil || u.Scheme != "http" || !strings.EqualFold(u.Host, r.Host) {
				forbid(w, blocked)
				return
			}
		}
		r.Body = http.MaxBytesReader(w, r.Body, maxForm)
		if err := r.ParseForm(); err != nil {
			http.Error(w, "The form is too large or not valid.", http.StatusBadRequest)
			return
		}
		cookie, err := r.Cookie(csrfCookie)
		field := r.PostForm.Get("csrf")
		if err != nil || !validToken(cookie.Value) || subtle.ConstantTimeCompare([]byte(cookie.Value), []byte(field)) != 1 {
			forbid(w, blocked)
			return
		}
		next(w, r)
	}
}

// tokenLength is the length of 32 bytes in base64url with no padding.
const tokenLength = 43

func validToken(s string) bool {
	b, err := base64.RawURLEncoding.DecodeString(s)
	return err == nil && len(b) == 32 && len(s) == tokenLength
}

func randomToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		// No entropy means no safe token; the server cannot run correctly.
		panic("admin: no random bytes: " + err.Error())
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// csrfToken returns the token of this browser, and sets the cookie when it has none.
func csrfToken(w http.ResponseWriter, r *http.Request) string {
	if c, err := r.Cookie(csrfCookie); err == nil && validToken(c.Value) {
		return c.Value
	}
	token := randomToken()
	http.SetCookie(w, &http.Cookie{
		Name: csrfCookie, Value: token, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode,
	})
	return token
}

// flash is a message for the page after a change. The admin reads it once. It lives in memory and not in the URL, so
// an invite code never reaches a log, the browser history or a Referer.
type flash struct {
	Text  string
	Code  string
	Error bool
	at    time.Time
}

type flashes struct {
	mu sync.Mutex
	m  map[string]flash
}

func (a *Admin) setFlash(w http.ResponseWriter, f flash) {
	f.at = a.now()
	id := randomToken()
	a.flash.mu.Lock()
	for k, old := range a.flash.m {
		if f.at.Sub(old.at) > flashTTL {
			delete(a.flash.m, k)
		}
	}
	if len(a.flash.m) >= maxFlashes {
		// Only one person uses this page, so the table stays tiny; past the cap, start again.
		clear(a.flash.m)
	}
	a.flash.m[id] = f
	a.flash.mu.Unlock()
	http.SetCookie(w, &http.Cookie{
		Name: flashCookie, Value: id, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode,
	})
}

// takeFlash returns the message for this browser and forgets it.
func (a *Admin) takeFlash(w http.ResponseWriter, r *http.Request) *flash {
	c, err := r.Cookie(flashCookie)
	if err != nil {
		return nil
	}
	http.SetCookie(w, &http.Cookie{Name: flashCookie, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
	a.flash.mu.Lock()
	defer a.flash.mu.Unlock()
	f, ok := a.flash.m[c.Value]
	delete(a.flash.m, c.Value)
	if !ok || a.now().Sub(f.at) > flashTTL {
		return nil
	}
	return &f
}

// done answers a POST: it sets the message and redirects to the list the form came from (PRG), with the same search
// and page.
func (a *Admin) done(w http.ResponseWriter, r *http.Request, page string, f flash) {
	a.setFlash(w, f)
	http.Redirect(w, r, returnTarget(r, page), http.StatusSeeOther)
}

// returnTarget is where a POST sends the admin back to. The form carries the address of its list in "return". Only
// the path of the same list and its q and page parameters are used, and the address is built here, so a value like
// "//host/x" or "https://host/" can never leave the admin.
func returnTarget(r *http.Request, page string) string {
	u, err := url.Parse(r.PostForm.Get("return"))
	if err != nil || u.Scheme != "" || u.Host != "" || u.Opaque != "" || u.User != nil || u.Path != "/"+page {
		return "/" + page
	}
	q, n := listParams(&http.Request{URL: u})
	return listURL(page, q, n)
}

func okMsg(format string, args ...any) flash { return flash{Text: fmt.Sprintf(format, args...)} }
func errMsg(format string, args ...any) flash {
	return flash{Text: fmt.Sprintf(format, args...), Error: true}
}

func (a *Admin) internal(w http.ResponseWriter, r *http.Request, page string, what string, err error) {
	a.opt.Log.Error("admin action failed", "action", what, "err", err.Error())
	a.done(w, r, page, errMsg("Could not %s. The server log has the details. Try again.", what))
}

// formKey reads the key id of a form and loads the key. It returns false when it has answered already.
func (a *Admin) formKey(w http.ResponseWriter, r *http.Request, page string) (store.Key, bool) {
	id, err := strconv.ParseInt(r.PostForm.Get("key"), 10, 64)
	if err == nil {
		var k store.Key
		k, err = a.opt.Store.KeyByID(r.Context(), id)
		if err == nil {
			return k, true
		}
		if !errors.Is(err, store.ErrNotFound) {
			a.internal(w, r, page, "read the key", err)
			return store.Key{}, false
		}
	}
	a.done(w, r, page, errMsg("That key does not exist. Reload the page and try again."))
	return store.Key{}, false
}

// formPath reads the character path of a form.
func formPath(r *http.Request) (characters.Path, bool) {
	segs := strings.Split(r.PostForm.Get("path"), "/")
	if len(segs) != 4 {
		return characters.Path{}, false
	}
	for _, s := range segs {
		if !ids.Pattern.MatchString(s) {
			return characters.Path{}, false
		}
	}
	return characters.Path{Flavor: segs[0], Region: segs[1], Realm: segs[2], Name: segs[3]}, true
}

func (a *Admin) approve(w http.ResponseWriter, r *http.Request) { a.decide(w, r, store.ShotsApproved) }
func (a *Admin) deny(w http.ResponseWriter, r *http.Request)    { a.decide(w, r, store.ShotsDenied) }

func (a *Admin) decide(w http.ResponseWriter, r *http.Request, state string) {
	k, ok := a.formKey(w, r, "requests")
	if !ok {
		return
	}
	changed, err := a.opt.Store.DecideScreenshots(r.Context(), k.ID, state)
	if err != nil {
		a.internal(w, r, "requests", "save the decision", err)
		return
	}
	if !changed {
		a.done(w, r, "requests", errMsg("Key %s has no pending request any more, so nothing changed.", k.Fingerprint()))
		return
	}
	a.opt.Log.Info("admin action", "action", "screenshots "+state, "key", k.Fingerprint())
	a.done(w, r, "requests", okMsg("Screenshots %s for key %s.", state, k.Fingerprint()))
}

// revokeKey blocks the key and then deletes its characters with their screenshots. The key is blocked first, so a
// failed deletion never leaves a working key. It runs for a key that is revoked already, so that a failed run can be
// repeated.
func (a *Admin) revokeKey(w http.ResponseWriter, r *http.Request) {
	k, ok := a.formKey(w, r, "keys")
	if !ok {
		return
	}
	if err := a.opt.Store.RevokeKey(r.Context(), k.ID); err != nil {
		a.internal(w, r, "keys", "revoke the key", err)
		return
	}
	n, err := a.opt.Chars.DeleteAllOfKey(r.Context(), k.ID)
	a.opt.Log.Info("admin action", "action", "revoke key", "key", k.Fingerprint(), "deleted", n)
	if err != nil {
		a.opt.Log.Error("admin action failed", "action", "delete the characters of a key", "key", k.Fingerprint(), "err", err.Error())
		a.done(w, r, "keys", errMsg("Key %s is revoked and %s deleted, but deleting the rest failed. The server log has the details. Revoke the key again to finish.", k.Fingerprint(), count(n)))
		return
	}
	a.done(w, r, "keys", okMsg("Key %s is revoked and %s deleted, screenshots included.", k.Fingerprint(), count(n)))
}

func (a *Admin) revokeScreenshots(w http.ResponseWriter, r *http.Request) {
	k, ok := a.formKey(w, r, "keys")
	if !ok {
		return
	}
	// The state changes first, so a screenshot upload that starts now is refused while the files go.
	if err := a.opt.Store.SetScreenshots(r.Context(), k.ID, store.ShotsDenied); err != nil {
		a.internal(w, r, "keys", "revoke the screenshots", err)
		return
	}
	n, err := a.opt.Chars.StripScreenshots(r.Context(), k.ID)
	a.opt.Log.Info("admin action", "action", "revoke screenshots", "key", k.Fingerprint(), "characters", n)
	if err != nil {
		a.opt.Log.Error("admin action failed", "action", "strip screenshots", "key", k.Fingerprint(), "err", err.Error())
		a.done(w, r, "keys", errMsg("Screenshots are denied for key %s and removed from %s, but removing them from every character failed. The server log has the details. Run this action again.", k.Fingerprint(), count(n)))
		return
	}
	a.done(w, r, "keys", okMsg("Screenshots are revoked for key %s. The images and their links are removed from %s.", k.Fingerprint(), count(n)))
}

func (a *Admin) createInvite(w http.ResponseWriter, r *http.Request) {
	days := defaultInviteDays
	if raw := strings.TrimSpace(r.PostForm.Get("days")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > maxInviteDays {
			a.done(w, r, "invites", errMsg("Days valid must be a whole number from 1 to %d.", maxInviteDays))
			return
		}
		days = n
	}
	note := cleanNote(r.PostForm.Get("note"))
	id, code, err := a.opt.Store.CreateInvite(r.Context(), note, time.Duration(days)*24*time.Hour)
	if err != nil {
		a.internal(w, r, "invites", "create the invite", err)
		return
	}
	a.opt.Log.Info("admin action", "action", "create invite", "invite", id, "days", days)
	a.done(w, r, "invites", flash{
		Text: fmt.Sprintf("Invite %d is ready and valid for %d days. This is the only time the code is shown. Copy it now.", id, days),
		Code: groupCode(code),
	})
}

// cleanNote keeps a note short and printable.
func cleanNote(s string) string {
	var b strings.Builder
	n := 0
	for _, r := range strings.TrimSpace(s) {
		if r < ' ' || r == 0x7f {
			continue
		}
		if n++; n > maxNoteRunes {
			break
		}
		b.WriteRune(r)
	}
	return b.String()
}

// groupCode writes the 16-character code in groups of 4. The server ignores the dashes.
func groupCode(code string) string {
	var parts []string
	for len(code) > 4 {
		parts, code = append(parts, code[:4]), code[4:]
	}
	return strings.Join(append(parts, code), "-")
}

func (a *Admin) revokeInvite(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PostForm.Get("invite"), 10, 64)
	if err == nil {
		err = a.opt.Store.RevokeInvite(r.Context(), id)
	}
	switch {
	case errors.Is(err, store.ErrNotFound) || errors.Is(err, strconv.ErrSyntax) || errors.Is(err, strconv.ErrRange):
		a.done(w, r, "invites", errMsg("That invite does not exist. Reload the page and try again."))
	case err != nil:
		a.internal(w, r, "invites", "revoke the invite", err)
	default:
		a.opt.Log.Info("admin action", "action", "revoke invite", "invite", id)
		a.done(w, r, "invites", okMsg("Invite %d is revoked. Its code no longer works.", id))
	}
}

func (a *Admin) deleteCharacter(w http.ResponseWriter, r *http.Request) {
	p, ok := formPath(r)
	if !ok {
		a.done(w, r, "characters", errMsg("That character path is not valid. Reload the page and try again."))
		return
	}
	err := a.opt.Chars.Delete(r.Context(), p, 0)
	switch {
	case errors.Is(err, store.ErrNotFound):
		a.done(w, r, "characters", errMsg("%s does not exist any more.", p))
	case err != nil:
		a.internal(w, r, "characters", "delete the character", err)
	default:
		a.opt.Log.Info("admin action", "action", "delete character", "path", p.String())
		a.done(w, r, "characters", okMsg("%s is deleted. Its page gives a 404 and the path is free to claim.", p))
	}
}

func (a *Admin) moveCharacter(w http.ResponseWriter, r *http.Request) {
	p, ok := formPath(r)
	if !ok {
		a.done(w, r, "characters", errMsg("That character path is not valid. Reload the page and try again."))
		return
	}
	fp := strings.ToLower(strings.TrimSpace(r.PostForm.Get("to")))
	noKey := errMsg("No key has the fingerprint %q. Copy the fingerprint from the Keys page.", fp)
	if !fingerprintPattern.MatchString(fp) {
		a.done(w, r, "characters", noKey)
		return
	}
	target, err := a.opt.Store.KeyByFingerprint(r.Context(), fp)
	if errors.Is(err, store.ErrNotFound) {
		a.done(w, r, "characters", noKey)
		return
	}
	if err != nil {
		a.internal(w, r, "characters", "read the key", err)
		return
	}
	switch err := a.opt.Chars.Move(r.Context(), p, target.ID); {
	case errors.Is(err, characters.ErrAlreadyOwner):
		a.done(w, r, "characters", errMsg("Key %s owns %s already, so nothing changed.", target.Fingerprint(), p))
	case errors.Is(err, store.ErrKeyRevoked):
		a.done(w, r, "characters", errMsg("Key %s is revoked. Choose a key that is not revoked.", target.Fingerprint()))
	case errors.Is(err, store.ErrNotFound):
		a.done(w, r, "characters", errMsg("%s does not exist any more.", p))
	case err != nil:
		a.internal(w, r, "characters", "move the character", err)
	default:
		a.opt.Log.Info("admin action", "action", "move claim", "path", p.String(), "to", target.Fingerprint())
		a.done(w, r, "characters", okMsg("%s now belongs to key %s. The old key can no longer upload it.", p, target.Fingerprint()))
	}
}

// count writes a number of characters: "1 character", "2 characters".
func count(n int) string {
	if n == 1 {
		return "1 character"
	}
	return fmt.Sprintf("%d characters", n)
}
