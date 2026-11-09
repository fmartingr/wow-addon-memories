package admin

import (
	"bytes"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// addKeys registers n keys straight in the store and returns them, oldest first.
func (e *env) addKeys(n int) []store.Key {
	e.t.Helper()
	var out []store.Key
	for i := 1; i <= n; i++ {
		pub, nonce := bytes.Repeat([]byte{byte(i)}, 32), bytes.Repeat([]byte{byte(i)}, 16)
		pub[0] = 0xAA
		if _, err := e.st.Register(bg, store.RegisterInput{Public: pub, Nonce: nonce}); err != nil {
			e.t.Fatal(err)
		}
		k, err := e.st.KeyByPublic(bg, pub)
		if err != nil {
			e.t.Fatal(err)
		}
		out = append(out, k)
	}
	return out
}

func (e *env) addInvites(n int, note string) {
	e.t.Helper()
	for i := 0; i < n; i++ {
		if _, _, err := e.st.CreateInvite(bg, fmt.Sprintf("%s %02d", note, i), time.Hour); err != nil {
			e.t.Fatal(err)
		}
	}
}

func (e *env) addClaims(key store.Key, n int) {
	e.t.Helper()
	for i := 0; i < n; i++ {
		name := fmt.Sprintf("char%02d", i)
		if _, err := e.st.CreateClaim(bg, store.Claim{Flavor: "wow", Region: "eu", Realm: "realm", Name: name, GUID: "Player-1-" + name, KeyID: key.ID}); err != nil {
			e.t.Fatal(err)
		}
	}
}

// rowCount counts the rows of the table of a page by their action cells.
func rowCount(body string) int { return strings.Count(body, `<td class="actions">`) }

func TestPagerBoundariesOnEveryList(t *testing.T) {
	lists := []struct {
		path string
		fill func(e *env, n int)
	}{
		{"keys", func(e *env, n int) { e.addKeys(n) }},
		{"invites", func(e *env, n int) { e.addInvites(n, "n") }},
		{"characters", func(e *env, n int) {
			if n > 0 {
				e.addClaims(e.addKeys(1)[0], n)
			}
		}},
		{"requests", func(e *env, n int) {
			for _, k := range e.addKeys(n) {
				if _, err := e.st.RequestScreenshots(bg, k.ID); err != nil {
					t.Fatal(err)
				}
			}
		}},
	}
	for _, l := range lists {
		for _, tc := range []struct {
			n, page          int
			rows             int
			label            string
			prev, next       string
			total            string
			requestedAsParam string
		}{
			{0, 1, 0, "Page 1 of 1", "", "", "0 results", ""},
			{25, 1, 25, "Page 1 of 1", "", "", "25 results", ""},
			{26, 1, 25, "Page 1 of 2", "", "/" + l.path + "?page=2", "26 results", ""},
			{26, 2, 1, "Page 2 of 2", "/" + l.path, "", "26 results", ""},
			{26, 3, 1, "Page 2 of 2", "/" + l.path, "", "26 results", ""},
			{26, 999999, 1, "Page 2 of 2", "/" + l.path, "", "26 results", ""},
			{26, 0, 25, "Page 1 of 2", "", "/" + l.path + "?page=2", "26 results", ""},
			{26, -2, 25, "Page 1 of 2", "", "/" + l.path + "?page=2", "26 results", ""},
			{26, 0, 25, "Page 1 of 2", "", "/" + l.path + "?page=2", "26 results", "abc"},
			{26, 0, 1, "Page 2 of 2", "/" + l.path, "", "26 results", "99999999999999999999999"},
			{51, 3, 1, "Page 3 of 3", "/" + l.path + "?page=2", "", "51 results", ""},
		} {
			e := newEnv(t)
			l.fill(e, tc.n)
			target := "/" + l.path + "?page=" + strconv.Itoa(tc.page)
			if tc.requestedAsParam != "" {
				target = "/" + l.path + "?page=" + tc.requestedAsParam
			}
			rec := e.browser().get(target)
			body := rec.Body.String()
			if rec.Code != http.StatusOK {
				t.Fatalf("GET %s = %d", target, rec.Code)
			}
			if got := rowCount(body); got != tc.rows {
				t.Errorf("%s with %d rows, GET %s: shows %d rows, want %d", l.path, tc.n, target, got, tc.rows)
			}
			mustContain(t, body, tc.label, tc.total)
			if (tc.prev == "") != !strings.Contains(body, `rel="prev"`) || (tc.prev != "" && !strings.Contains(body, `<a href="`+tc.prev+`" rel="prev">Previous</a>`)) {
				t.Errorf("%s %s: wrong Previous link, want %q", l.path, target, tc.prev)
			}
			if (tc.next == "") != !strings.Contains(body, `rel="next"`) || (tc.next != "" && !strings.Contains(body, `<a href="`+tc.next+`" rel="next">Next</a>`)) {
				t.Errorf("%s %s: wrong Next link, want %q", l.path, target, tc.next)
			}
		}
	}
}

func TestListsAreOrderedAndPagesDoNotOverlap(t *testing.T) {
	e := newEnv(t)
	keys := e.addKeys(30)
	br := e.browser()
	p1 := br.get("/keys").Body.String()
	p2 := br.get("/keys?page=2").Body.String()
	// Newest first: key 30 opens page 1, key 6 is the last of page 1, key 5 opens page 2.
	for i, want := range map[int]string{30: p1, 6: p1, 5: p2, 1: p2} {
		fp := keys[i-1].Fingerprint()
		other := p1
		if want == p1 {
			other = p2
		}
		if !strings.Contains(want, fp) || strings.Contains(other, fp) {
			t.Errorf("key %d is not on exactly the expected page", i)
		}
	}
}

func TestSearchOnEveryList(t *testing.T) {
	e := newEnv(t)
	_, code, _ := e.st.CreateInvite(bg, "for Ana", time.Hour)
	ana := newClient(1)
	if _, err := e.st.Register(bg, store.RegisterInput{Public: ana.public(), Nonce: bytes.Repeat([]byte{1}, 16), Invite: code, RequireInvite: true}); err != nil {
		t.Fatal(err)
	}
	ben, kBen := e.registered(2)
	e.st.RequestScreenshots(bg, e.row(ana).ID)
	e.st.RequestScreenshots(bg, kBen.ID)
	e.st.SetScreenshots(bg, kBen.ID, store.ShotsApproved)
	e.addInvites(1, "spare")
	e.st.CreateInvite(bg, "gone", time.Hour)
	e.addClaims(kBen, 1)
	br := e.browser()

	present := func(path, q string, want, absent []string) {
		t.Helper()
		body := br.get("/" + path + "?q=" + url.QueryEscape(q)).Body.String()
		for _, w := range want {
			if !strings.Contains(body, w) {
				t.Errorf("%s search %q lacks %s", path, q, w)
			}
		}
		for _, a := range absent {
			if strings.Contains(body, a) {
				t.Errorf("%s search %q shows %s", path, q, a)
			}
		}
	}
	a, b := ana.fingerprint(), ben.fingerprint()
	present("keys", a, []string{a}, []string{b})
	present("keys", strings.ToUpper(b[:8]), []string{b}, []string{a})
	present("keys", "ana", []string{a}, []string{b})
	present("keys", "APPROVED", []string{b}, []string{a})
	present("keys", "pending", []string{a}, []string{b})
	present("requests", "ana", []string{a}, []string{b})
	present("requests", b, nil, []string{"<code>" + a, "<code>" + b})
	present("requests", "approved", nil, []string{"<code>" + a, "<code>" + b})
	present("characters", b, []string{"char00"}, nil)
	present("characters", a, nil, []string{"char00"})
	present("invites", "spare", []string{"spare 00"}, []string{"for Ana", "gone"})
	present("invites", "unused", []string{"spare 00", "gone"}, []string{"for Ana"})
	present("invites", "used", []string{"for Ana"}, []string{"spare 00", "gone"})
	present("invites", "nothing", nil, []string{"for Ana", "spare", "gone"})
	mustContain(t, br.get("/invites?q=nothing").Body.String(), "No invite matches the search", "0 results")
	mustContain(t, br.get("/keys?q=nothing").Body.String(), "No key matches the search")
	mustContain(t, br.get("/requests?q=nothing").Body.String(), "No request matches the search")

	e.advance(2 * time.Hour)
	present("invites", "expired", []string{"spare 00", "gone"}, []string{"for Ana"})
	present("invites", "unused", nil, []string{"spare 00", "gone", "for Ana"})
}

func TestSearchTreatsWildcardsAsText(t *testing.T) {
	e := newEnv(t)
	for _, note := range []string{"100% sure", "a_b", "axb", `back\slash`} {
		e.st.CreateInvite(bg, note, time.Hour)
	}
	br := e.browser()
	for q, want := range map[string][]string{
		"%":       {"100% sure"},
		"0% s":    {"100% sure"},
		"_":       {"a_b"},
		"a_b":     {"a_b"},
		`\`:       {`back\slash`},
		`\%`:      nil,
		"a%b":     nil,
		"%%":      nil,
		"axb":     {"axb"},
		"A_B":     {"a_b"},
		"sure%":   nil,
		"100%_su": nil,
	} {
		body := br.get("/invites?q=" + url.QueryEscape(q)).Body.String()
		if got := rowCountInvites(body); got != len(want) {
			t.Errorf("search %q: %d invites, want %d", q, got, len(want))
		}
		for _, w := range want {
			if !strings.Contains(body, "<td>"+w+"</td>") {
				t.Errorf("search %q lacks %q", q, w)
			}
		}
	}
}

func rowCountInvites(body string) int { return strings.Count(body, "<td>Unused</td>") }

func TestSearchIsKeptInThePagerLinks(t *testing.T) {
	e := newEnv(t)
	e.addInvites(30, "bulk")
	e.addInvites(5, "other")
	br := e.browser()
	p1 := br.get("/invites?q=bulk").Body.String()
	mustContain(t, p1, "30 results", "Page 1 of 2", `<a href="/invites?page=2&amp;q=bulk" rel="next">Next</a>`, `value="bulk"`)
	p2 := br.get("/invites?q=bulk&page=2").Body.String()
	mustContain(t, p2, "Page 2 of 2", `<a href="/invites?q=bulk" rel="prev">Previous</a>`)
	if rowCount(p2) != 5 || strings.Contains(p2, "other") {
		t.Errorf("page 2 of the search shows %d rows", rowCount(p2))
	}
	mustContain(t, br.get("/invites?q="+url.QueryEscape("a&b=c d")).Body.String(), `value="a&amp;b=c d"`)
}

func TestChangeReturnsToTheSameListPageAndSearch(t *testing.T) {
	e := newEnv(t)
	e.addInvites(30, "bulk")
	br := e.browser()
	page := br.get("/invites?q=bulk&page=2").Body.String()
	mustContain(t, page, `name="return" value="/invites?page=2&amp;q=bulk"`)

	var inviteID string
	invs := e.invites()
	inviteID = strconv.FormatInt(invs[len(invs)-1].ID, 10)
	rec := br.post("/invites/revoke", form("invite", inviteID, "return", "/invites?page=2&q=bulk"))
	if got := rec.Header().Get("Location"); rec.Code != http.StatusSeeOther || got != "/invites?page=2&q=bulk" {
		t.Errorf("redirect = %d %q, want the same page and search", rec.Code, got)
	}
	keys := e.addKeys(30)
	e.st.RequestScreenshots(bg, keys[0].ID)
	for _, tc := range []struct{ path, ret, want string }{
		{"/requests/approve", "/requests?page=1&q=", "/requests"},
		{"/keys/screenshots", "/keys?page=2", "/keys?page=2"},
		{"/keys/revoke", "/keys?q=aa&page=3", "/keys?page=3&q=aa"},
		{"/characters/delete", "/characters?q=x", "/characters?q=x"},
		{"/characters/move", "/characters?page=4", "/characters?page=4"},
		{"/invites/create", "", "/invites"},
		{"/characters/delete", "/characters?q=x&evil=1#frag", "/characters?q=x"},
	} {
		f := form("key", id(keys[0]), "path", "wow/eu/r/n", "to", "zzzz", "return", tc.ret)
		if rec := br.post(tc.path, f); rec.Header().Get("Location") != tc.want {
			t.Errorf("POST %s with return %q redirects to %q, want %q", tc.path, tc.ret, rec.Header().Get("Location"), tc.want)
		}
	}
}

func TestChangeRefusesToRedirectAnywhereElse(t *testing.T) {
	e := newEnv(t)
	k := e.addKeys(1)[0]
	br := e.browser()
	for _, ret := range []string{
		"//evil.example/keys",
		"//evil.example",
		"https://evil.example/keys",
		"http://127.0.0.1:8081/keys",
		`/\evil.example`,
		"/\\/evil.example",
		"javascript:alert(1)",
		"mailto:a@b.c",
		"keys",
		"/invites",
		"/keys/revoke",
		"/keys/../invites",
		"/%2f%2fevil.example",
		"\t//evil.example",
		"/keys\n//evil.example",
		"%",
		"/keys?q=%zz",
	} {
		rec := br.post("/keys/screenshots", form("key", id(k), "return", ret))
		loc := rec.Header().Get("Location")
		if rec.Code != http.StatusSeeOther || strings.Contains(loc, "evil") || (loc != "/keys" && !strings.HasPrefix(loc, "/keys?")) {
			t.Errorf("return %q redirects to %d %q, want a local /keys address", ret, rec.Code, loc)
		}
		if ret != "/keys?q=%zz" && loc != "/keys" {
			t.Errorf("return %q redirects to %q, want plain /keys", ret, loc)
		}
	}
}
