package httpserver

import (
	"net/http"
	"strings"
	"testing"
)

func TestLanguageLinkSetsTheCookieAndRedirects(t *testing.T) {
	s := newSite(t)
	rec := s.get("/?lang=fr")
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "/" {
		t.Fatalf("GET /?lang=fr = %d, Location %q", rec.Code, rec.Header().Get("Location"))
	}
	if got := rec.Header().Get("Set-Cookie"); got != "lang=fr; Path=/; Max-Age=31536000; SameSite=Lax" {
		t.Errorf("Set-Cookie = %q", got)
	}
	checkSecurityHeaders(t, rec, "redirect")

	home := s.get("/", "Cookie", "lang=fr")
	if home.Code != http.StatusOK || !strings.Contains(home.Body.String(), `<html lang="fr">`) || !strings.Contains(home.Body.String(), "Ce que Memories enregistre") {
		t.Errorf("home with the cookie: %d, not French", home.Code)
	}
	if home.Header().Get("Vary") != "Cookie, Accept-Language" {
		t.Errorf("Vary = %q", home.Header().Get("Vary"))
	}
	checkSecurityHeaders(t, home, "home")
}

func TestHomeFollowsAcceptLanguage(t *testing.T) {
	s := newSite(t)
	if body := s.get("/", "Accept-Language", "es").Body.String(); !strings.Contains(body, "Lo que registra Memories") {
		t.Error("Accept-Language: es did not give Spanish")
	}
	if body := s.get("/").Body.String(); !strings.Contains(body, "What Memories records") {
		t.Error("no language input did not give English")
	}
}

func TestNotFoundPageFollowsTheCookie(t *testing.T) {
	s := newSite(t)
	rec := s.get("/nothing", "Cookie", "lang=pt")
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "Página não encontrada") {
		t.Errorf("404 with the cookie: %d, not Portuguese", rec.Code)
	}
	if rec.Header().Get("Vary") != "Cookie, Accept-Language" {
		t.Errorf("Vary = %q", rec.Header().Get("Vary"))
	}
	if r := s.get("/nothing?lang=pt"); r.Code != http.StatusSeeOther || r.Header().Get("Location") != "/nothing" {
		t.Errorf("GET /nothing?lang=pt = %d, Location %q", r.Code, r.Header().Get("Location"))
	}
}

func TestLanguageQueryWithAnUnknownCodeSetsNoCookie(t *testing.T) {
	s := newSite(t)
	for _, target := range []string{"/?lang=<script>", "/?lang=%3Cscript%3E", "/?lang=xx&foo=1", "/?lang=de-AT", "/?lang=ru", "/?lang="} {
		rec := s.get(target)
		if rec.Code != http.StatusSeeOther || rec.Header().Get("Set-Cookie") != "" || strings.Contains(rec.Header().Get("Location"), "script") {
			t.Errorf("GET %s = %d, Location %q, cookie %q", target, rec.Code, rec.Header().Get("Location"), rec.Header().Get("Set-Cookie"))
		}
	}
	if rec := s.get("/?lang=xx&foo=1"); rec.Header().Get("Location") != "/?foo=1" {
		t.Errorf("Location = %q, want the other query kept", rec.Header().Get("Location"))
	}
}

func TestLanguageRedirectKeepsTheRequestOnThisHost(t *testing.T) {
	s := newSite(t)
	rec := s.get("//evil.example/path?lang=de")
	if loc := rec.Header().Get("Location"); strings.HasPrefix(loc, "//") || !strings.HasPrefix(loc, "/") {
		t.Errorf("Location = %q, want a path on this host", loc)
	}
}

func TestSecureCookieFollowsTheSiteURL(t *testing.T) {
	s := newSiteWith(t, map[string]string{"MEMORIES_SITE_URL": "https://memories.example"})
	if c := s.get("/?lang=de").Result().Cookies(); len(c) != 1 || !c[0].Secure || c[0].HttpOnly {
		t.Errorf("cookies = %v, want Secure and not HttpOnly", c)
	}
}

func TestCharacterPageLanguage(t *testing.T) {
	s := newSite(t)
	s.upload("eu-brumamar-nandu")
	for name, tc := range map[string]struct {
		hdr  []string
		want string
	}{
		"cookie":  {[]string{"Cookie", "lang=de"}, `<html lang="de" data-lang-from="cookie"`},
		"default": {nil, `<html lang="en" data-lang-from="default"`},
		"header":  {[]string{"Accept-Language", "fr"}, `<html lang="fr" data-lang-from="header"`},
		"unknown": {[]string{"Cookie", "lang=zz"}, `<html lang="en" data-lang-from="default"`},
	} {
		t.Run(name, func(t *testing.T) {
			rec := s.get(brumamar+"/", tc.hdr...)
			if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), tc.want) {
				t.Errorf("%d, page lacks %q", rec.Code, tc.want)
			}
			if rec.Header().Get("Vary") != "Cookie, Accept-Language" {
				t.Errorf("Vary = %q", rec.Header().Get("Vary"))
			}
			checkPageHeaders(t, rec, "page")
		})
	}
	rec := s.get(brumamar + "/?lang=it")
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != brumamar+"/" || rec.Header().Get("Set-Cookie") == "" {
		t.Errorf("character page ?lang=it = %d, Location %q", rec.Code, rec.Header().Get("Location"))
	}
	checkSecurityHeaders(t, rec, "character redirect")
}

func TestDataFilesIgnoreTheLanguageQuery(t *testing.T) {
	s := newSite(t)
	s.upload("eu-brumamar-nandu")
	rec := s.get(brumamar + "/data/entry.json?lang=de")
	if rec.Code != http.StatusOK || rec.Header().Get("Set-Cookie") != "" {
		t.Errorf("data file ?lang=de = %d, cookie %q; want 200 and no cookie", rec.Code, rec.Header().Get("Set-Cookie"))
	}
	if rec := s.get("/api/v1/info?lang=de"); rec.Code != http.StatusOK || rec.Header().Get("Set-Cookie") != "" {
		t.Errorf("API ?lang=de = %d", rec.Code)
	}
}

func TestViewerIndexHasTheLanguagePicker(t *testing.T) {
	s := newSite(t)
	s.upload("eu-brumamar-nandu")
	body := s.get(brumamar + "/").Body.String()
	for _, code := range []string{"en", "de", "fr", "es", "it", "pt"} {
		if !strings.Contains(body, `href="?lang=`+code+`"`) {
			t.Errorf("character page has no picker link for %s", code)
		}
	}
}
