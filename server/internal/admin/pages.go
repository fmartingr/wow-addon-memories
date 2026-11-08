package admin

import (
	"bytes"
	"errors"
	"fmt"
	"html/template"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// view is the data of every page. A page uses the fields it needs.
type view struct {
	Page    string
	CSRF    string
	Flash   *flash
	SiteURL string

	Requests   []keyView
	Keys       []keyView
	Invites    []inviteView
	Characters []characterView
	Query      string
	Limit      int
	Truncated  bool
	DefaultDay int
}

type keyView struct {
	ID          int64
	Fingerprint string
	Created     time.Time
	LastSeen    time.Time
	Note        string
	Screenshots string
	Revoked     bool
	Characters  int64
	DataBytes   int64
	ShotBytes   int64
}

type inviteView struct {
	ID      int64
	Note    string
	Created time.Time
	Expires time.Time
	State   string
	Active  bool
}

type characterView struct {
	Path      string
	GUID      string
	Owner     string
	Revoked   bool
	Steps     int64
	Updated   time.Time
	DataBytes int64
	ShotBytes int64
}

func when(t time.Time) string {
	if t.IsZero() {
		return "never"
	}
	return t.UTC().Format("2006-01-02 15:04") + " UTC"
}

var funcs = template.FuncMap{
	"when": when,
	"size": func(n int64) string {
		const unit = 1024
		if n < unit {
			return fmt.Sprintf("%d B", n)
		}
		f, suffix := float64(n), "KMGT"
		i := -1
		for f >= unit && i < len(suffix)-1 {
			f /= unit
			i++
		}
		return fmt.Sprintf("%.1f %ciB", f, suffix[i])
	},
}

var pageNames = []string{"requests", "keys", "invites", "characters"}

func parseTemplates() (map[string]*template.Template, error) {
	pages := map[string]*template.Template{}
	for _, name := range pageNames {
		t, err := template.New("base.html").Funcs(funcs).ParseFS(templateFS, "templates/base.html", "templates/"+name+".html")
		if err != nil {
			return nil, err
		}
		pages[name] = t
	}
	return pages, nil
}

// page serves one GET page. fill adds the data of the page; an error from it gives a plain 500 page.
func (a *Admin) page(name string, fill func(r *http.Request, v *view) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		v := &view{Page: name, SiteURL: a.opt.SiteURL}
		v.CSRF = csrfToken(w, r)
		// The message is taken only once the page can show it: it may hold an invite code that is shown once.
		if err := fill(r, v); err != nil {
			a.opt.Log.Error("admin page failed", "page", name, "err", err.Error())
			http.Error(w, "The page could not be built. The server log has the details. Reload the page to try again.", http.StatusInternalServerError)
			return
		}
		v.Flash = a.takeFlash(w, r)
		var buf bytes.Buffer
		if err := a.pages[name].Execute(&buf, v); err != nil {
			a.opt.Log.Error("admin page failed", "page", name, "err", err.Error())
			http.Error(w, "The page could not be built. The server log has the details. Reload the page to try again.", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(buf.Bytes())
	}
}

func toKeyViews(rows []store.KeyRow) []keyView {
	out := make([]keyView, 0, len(rows))
	for _, k := range rows {
		kv := keyView{
			ID: k.ID, Fingerprint: k.Fingerprint(), Created: time.Unix(k.Created, 0), Note: k.InviteNote,
			Screenshots: k.Screenshots, Revoked: k.Revoked, Characters: k.Characters, DataBytes: k.DataBytes, ShotBytes: k.ShotBytes,
		}
		if k.LastSeen != 0 {
			kv.LastSeen = time.Unix(k.LastSeen, 0)
		}
		out = append(out, kv)
	}
	return out
}

// limited trims rows fetched with listLimit+1 to listLimit and reports whether more rows exist.
func limited[T any](v *view, rows []T) []T {
	v.Limit = listLimit
	if len(rows) > listLimit {
		v.Truncated = true
		return rows[:listLimit]
	}
	return rows
}

func (a *Admin) requestsPage(r *http.Request, v *view) error {
	rows, err := a.opt.Store.ListKeys(r.Context(), true, listLimit+1)
	v.Requests = toKeyViews(limited(v, rows))
	return err
}

func (a *Admin) keysPage(r *http.Request, v *view) error {
	rows, err := a.opt.Store.ListKeys(r.Context(), false, listLimit+1)
	v.Keys = toKeyViews(limited(v, rows))
	return err
}

func (a *Admin) invitesPage(r *http.Request, v *view) error {
	rows, err := a.opt.Store.ListInvites(r.Context(), listLimit+1)
	if err != nil {
		return err
	}
	rows = limited(v, rows)
	now := a.opt.Store.Now().Unix()
	for _, i := range rows {
		iv := inviteView{ID: i.ID, Note: i.Note, Created: time.Unix(i.Created, 0), Expires: time.Unix(i.Expires, 0)}
		// A use comes first: a revoke sent from a page that was open before the use does not hide who used it.
		switch {
		case i.UsedBy != "":
			iv.State = "Used by key " + i.UsedBy + " on " + when(time.Unix(i.UsedAt, 0))
		case i.Revoked:
			iv.State = "Revoked"
		case i.Expires <= now:
			iv.State = "Expired"
		default:
			iv.State, iv.Active = "Unused", true
		}
		v.Invites = append(v.Invites, iv)
	}
	v.DefaultDay = defaultInviteDays
	return nil
}

var fingerprintPattern = regexp.MustCompile(`^[0-9a-f]{16}$`)

const maxQueryRunes = 200

func (a *Admin) charactersPage(r *http.Request, v *view) error {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if rs := []rune(q); len(rs) > maxQueryRunes {
		q = string(rs[:maxQueryRunes])
	}
	v.Query = q
	// A key fingerprint lists the characters of that key.
	var keyID int64
	search := q
	if fingerprintPattern.MatchString(strings.ToLower(q)) {
		k, err := a.opt.Store.KeyByFingerprint(r.Context(), q)
		switch {
		case err == nil:
			keyID, search = k.ID, ""
		case !errors.Is(err, store.ErrNotFound):
			return err
		}
	}
	rows, err := a.opt.Store.SearchClaims(r.Context(), search, keyID, listLimit+1)
	if err != nil {
		return err
	}
	for _, c := range limited(v, rows) {
		v.Characters = append(v.Characters, characterView{
			Path: c.Path(), GUID: c.GUID, Owner: store.Fingerprint(c.OwnerKey), Revoked: c.OwnerRevoked, Steps: c.Steps,
			Updated: time.Unix(c.Updated, 0), DataBytes: c.DataBytes, ShotBytes: c.ShotBytes,
		})
	}
	return nil
}
