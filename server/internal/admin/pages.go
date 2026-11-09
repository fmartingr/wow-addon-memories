package admin

import (
	"bytes"
	"errors"
	"fmt"
	"html/template"
	"math"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
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
	DefaultDay int

	// Query, PageNo, Pages, Total and the links drive the search box and the pager of a list. Return is where the
	// forms of the page send the admin back to after a change.
	Query       string
	Placeholder string
	PageNo      int
	Pages       int
	Total       int
	PrevURL     string
	NextURL     string
	Return      string
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

// listURL is the address of a page of a list. It leaves out the defaults, so the first page of a list with no search
// is the plain path.
func listURL(page, q string, n int) string {
	v := url.Values{}
	if q != "" {
		v.Set("q", q)
	}
	if n > 1 {
		v.Set("page", strconv.Itoa(n))
	}
	if len(v) == 0 {
		return "/" + page
	}
	return "/" + page + "?" + v.Encode()
}

// listParams reads the search text and the requested page of a list. A page that is not a number, or is below 1, is
// page 1; a page too large for an integer is a very high page, which the store clamps to the last one.
func listParams(r *http.Request) (q string, page int) {
	q = strings.TrimSpace(r.URL.Query().Get("q"))
	if rs := []rune(q); len(rs) > maxQueryRunes {
		q = strings.TrimSpace(string(rs[:maxQueryRunes]))
	}
	raw := r.URL.Query().Get("page")
	n, err := strconv.Atoi(raw)
	switch {
	case errors.Is(err, strconv.ErrRange) && !strings.HasPrefix(raw, "-"):
		return q, math.MaxInt32
	case err != nil || n < 1:
		return q, 1
	}
	return q, n
}

// setPager fills the search box and the pager of v with the listing that the store returned.
func setPager[T any](v *view, q, placeholder string, l store.Listing[T]) {
	v.Query, v.Placeholder = q, placeholder
	v.PageNo, v.Pages, v.Total = l.Page, l.Pages, l.Total
	v.Return = listURL(v.Page, q, l.Page)
	if l.Page > 1 {
		v.PrevURL = listURL(v.Page, q, l.Page-1)
	}
	if l.Page < l.Pages {
		v.NextURL = listURL(v.Page, q, l.Page+1)
	}
}

func (a *Admin) requestsPage(r *http.Request, v *view) error {
	q, page := listParams(r)
	l, err := a.opt.Store.ListRequests(r.Context(), q, page, pageSize)
	if err != nil {
		return err
	}
	v.Requests = toKeyViews(l.Rows)
	setPager(v, q, "Fingerprint or invite note", l)
	return nil
}

func (a *Admin) keysPage(r *http.Request, v *view) error {
	q, page := listParams(r)
	l, err := a.opt.Store.ListKeys(r.Context(), q, page, pageSize)
	if err != nil {
		return err
	}
	v.Keys = toKeyViews(l.Rows)
	setPager(v, q, "Fingerprint, invite note or screenshot state", l)
	return nil
}

func (a *Admin) invitesPage(r *http.Request, v *view) error {
	q, page := listParams(r)
	l, err := a.opt.Store.ListInvites(r.Context(), q, page, pageSize)
	if err != nil {
		return err
	}
	now := a.opt.Store.Now().Unix()
	for _, i := range l.Rows {
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
	setPager(v, q, "Note or state: unused, used, expired, revoked", l)
	return nil
}

var fingerprintPattern = regexp.MustCompile(`^[0-9a-f]{16}$`)

const maxQueryRunes = 200

func (a *Admin) charactersPage(r *http.Request, v *view) error {
	q, page := listParams(r)
	l, err := a.opt.Store.SearchClaims(r.Context(), q, page, pageSize)
	if err != nil {
		return err
	}
	for _, c := range l.Rows {
		v.Characters = append(v.Characters, characterView{
			Path: c.Path(), GUID: c.GUID, Owner: store.Fingerprint(c.OwnerKey), Revoked: c.OwnerRevoked, Steps: c.Steps,
			Updated: time.Unix(c.Updated, 0), DataBytes: c.DataBytes, ShotBytes: c.ShotBytes,
		})
	}
	setPager(v, q, "Path, GUID or key fingerprint", l)
	return nil
}
