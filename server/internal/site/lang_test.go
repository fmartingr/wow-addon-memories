package site

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestFromTag(t *testing.T) {
	for tag, want := range map[string]Lang{
		"en": "en", "en-GB": "en", "enUS": "en", "enGB": "en", "de": "de", "de-AT": "de", "deDE": "de", "DE": "de",
		"fr": "fr", "frFR": "fr", "es": "es", "es-419": "es", "esES": "es", "esMX": "es", "it": "it", "itIT": "it",
		"pt": "pt", "pt-PT": "pt", "ptBR": "pt", "ptPT": "pt", "pt_BR": "pt", " de ": "de",
	} {
		if got, ok := FromTag(tag); !ok || got != want {
			t.Errorf("FromTag(%q) = %q, %v; want %q", tag, got, ok, want)
		}
	}
	for _, tag := range []string{"", "*", "ru", "ruRU", "koKR", "zhCN", "zh-TW", "xx", "d", "deutsch", "<script>", "en-", "-de"} {
		if got, ok := FromTag(tag); ok {
			t.Errorf("FromTag(%q) = %q, want no match", tag, got)
		}
	}
}

func TestPick(t *testing.T) {
	for name, tc := range map[string]struct {
		target, cookie, accept string
		lang                   Lang
		from                   string
	}{
		"nothing":                {"/", "", "", "en", "default"},
		"query":                  {"/?lang=fr", "", "", "fr", "query"},
		"query beats cookie":     {"/?lang=fr", "de", "es", "fr", "query"},
		"first query wins":       {"/?lang=it&lang=de", "", "", "it", "query"},
		"unknown query":          {"/?lang=xx", "de", "es", "de", "cookie"},
		"unknown query, nothing": {"/?lang=xx", "", "", "en", "default"},
		"script query":           {"/?lang=%3Cscript%3E", "", "", "en", "default"},
		"empty query":            {"/?lang=", "", "fr", "fr", "header"},
		"cookie":                 {"/", "de", "", "de", "cookie"},
		"cookie beats header":    {"/", "de", "es", "de", "cookie"},
		"unknown cookie":         {"/", "ru", "es", "es", "header"},
		"cookie is a tag":        {"/", "de-AT", "", "en", "default"},
		"header":                 {"/", "", "pt", "pt", "header"},
		"header q order":         {"/", "", "de-CH;q=0.9, fr;q=1.0", "fr", "header"},
		"header first at tie":    {"/", "", "it, de", "it", "header"},
		"header pt-PT":           {"/", "", "pt-PT", "pt", "header"},
		"header skips unknown":   {"/", "", "ru, ko;q=0.9, es;q=0.1", "es", "header"},
		"header star":            {"/", "", "*", "en", "default"},
		"header garbage":         {"/", "", ";;;,q=,,;q=x, de;q=abc", "en", "default"},
		"header q zero":          {"/", "", "de;q=0, fr;q=0.2", "fr", "header"},
		"header only q zero":     {"/", "", "de;q=0", "en", "default"},
		"header q above one":     {"/", "", "de;q=7, fr", "fr", "header"},
		"header spaces":          {"/", "", "  de ; q=0.5 , fr ; q=0.8 ", "fr", "header"},
		"header other params":    {"/", "", "fr;q=0.5, de;level=1;q=0.9", "de", "header"},
		"header upper Q":         {"/", "", "fr;q=0.5, it;Q=0.8", "it", "header"},
		"header 10 KiB":          {"/", "", strings.Repeat("x", 10<<10) + ",de", "en", "default"},
		"header early in 10 KiB": {"/", "", "de," + strings.Repeat("x", 10<<10), "de", "header"},
		"header cut before q": {"/", "", "en;q=0.9, " + strings.Repeat("x", maxAcceptLang-len("en;q=0.9, , de")) + ", de;q=0.1",
			"en", "header"},
	} {
		t.Run(name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, tc.target, nil)
			if tc.cookie != "" {
				r.AddCookie(&http.Cookie{Name: "lang", Value: tc.cookie})
			}
			if tc.accept != "" {
				r.Header.Set("Accept-Language", tc.accept)
			}
			if lang, from := Pick(r); lang != tc.lang || from != tc.from {
				t.Errorf("Pick = %q, %q; want %q, %q", lang, from, tc.lang, tc.from)
			}
		})
	}
}

func choiceRig(secure bool) http.Handler {
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("page")) })
	return LangChoice(secure, ok)
}

func TestLangChoiceSetsTheCookieAndRedirects(t *testing.T) {
	for name, tc := range map[string]struct {
		method, target string
		location       string
		cookie         bool
	}{
		"home":          {"GET", "/?lang=fr", "/", true},
		"head":          {"HEAD", "/?lang=de", "/", true},
		"keeps query":   {"GET", "/?lang=de&foo=1", "/?foo=1", true},
		"keeps order":   {"GET", "/?b=2&lang=de&a=1", "/?b=2&a=1", true},
		"first of two":  {"GET", "/?lang=es&lang=de", "/", true},
		"character":     {"GET", "/wow/eu/realm/name/?lang=pt", "/wow/eu/realm/name/", true},
		"missing path":  {"GET", "/nothing?lang=it", "/nothing", true},
		"unknown code":  {"GET", "/?lang=xx", "/", false},
		"script":        {"GET", "/?lang=%3Cscript%3Ex", "/", false},
		"empty":         {"GET", "/?lang=", "/", false},
		"slashes":       {"GET", "//evil.example/x?lang=de", "/evil.example/x", true},
		"escaped path":  {"GET", "/a%20b?lang=de", "/a%20b", true},
		"first unknown": {"GET", "/?lang=xx&lang=de", "/", false},
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			choiceRig(false).ServeHTTP(rec, httptest.NewRequest(tc.method, tc.target, nil))
			if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != tc.location {
				t.Fatalf("%d, Location %q; want 303 to %q", rec.Code, rec.Header().Get("Location"), tc.location)
			}
			cookies := rec.Result().Cookies()
			if tc.cookie != (len(cookies) == 1) {
				t.Fatalf("cookies = %v, want a cookie: %v", cookies, tc.cookie)
			}
			if tc.cookie {
				c := cookies[0]
				if c.Name != "lang" || c.Path != "/" || c.MaxAge != 31536000 || c.SameSite != http.SameSiteLaxMode || c.HttpOnly || c.Secure {
					t.Errorf("cookie = %+v", c)
				}
				if !strings.Contains(rec.Header().Get("Set-Cookie"), "lang="+c.Value+"; Path=/; Max-Age=31536000; SameSite=Lax") {
					t.Errorf("Set-Cookie = %q", rec.Header().Get("Set-Cookie"))
				}
			}
		})
	}
}

func TestLangChoiceLeavesOtherRequestsAlone(t *testing.T) {
	for name, tc := range map[string]struct{ method, target string }{
		"no lang":     {"GET", "/?x=1"},
		"data file":   {"GET", "/wow/eu/realm/name/data/journey.jsonl?lang=de"},
		"asset":       {"GET", "/_/app.mjs?lang=de"},
		"api":         {"GET", "/api/v1/info?lang=de"},
		"post":        {"POST", "/?lang=de"},
		"api upload":  {"PUT", "/api/v1/x?lang=de"},
		"delete":      {"DELETE", "/?lang=de"},
		"screenshots": {"GET", "/wow/eu/realm/name/data/screenshots/a.jpg?lang=de"},
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			choiceRig(false).ServeHTTP(rec, httptest.NewRequest(tc.method, tc.target, nil))
			if rec.Body.String() != "page" || rec.Header().Get("Set-Cookie") != "" {
				t.Errorf("%d %q cookie %q; want the handler and no cookie", rec.Code, rec.Body, rec.Header().Get("Set-Cookie"))
			}
		})
	}
}

func TestLangChoiceSecureCookie(t *testing.T) {
	rec := httptest.NewRecorder()
	choiceRig(true).ServeHTTP(rec, httptest.NewRequest("GET", "/?lang=de", nil))
	if c := rec.Result().Cookies(); len(c) != 1 || !c[0].Secure {
		t.Errorf("cookies = %v, want a Secure cookie", c)
	}
	rec = httptest.NewRecorder()
	choiceRig(false).ServeHTTP(rec, httptest.NewRequest("GET", "https://example.test/?lang=de", nil))
	if c := rec.Result().Cookies(); len(c) != 1 || !c[0].Secure {
		t.Errorf("cookies over TLS = %v, want a Secure cookie", c)
	}
}
