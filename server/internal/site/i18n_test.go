package site

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestEveryLanguageHasTheSameKeysAsEnglish(t *testing.T) {
	for _, l := range Langs {
		if len(messages[l]) != len(messages["en"]) {
			t.Errorf("%s has %d keys, English has %d", l, len(messages[l]), len(messages["en"]))
		}
		for k, v := range messages[l] {
			en, ok := messages["en"][k]
			if !ok {
				t.Errorf("%s has the key %q that English lacks", l, k)
			}
			if strings.TrimSpace(v) == "" {
				t.Errorf("%s %q is empty", l, k)
			}
			if l != "en" && v == en {
				t.Errorf("%s %q is the English text", l, k)
			}
			if strings.Contains(v, "<") != strings.HasSuffix(k, ".html") {
				t.Errorf("%s %q: markup and the .html suffix do not match", l, k)
			}
		}
	}
	for _, a := range Addons {
		if _, ok := messages["en"]["addon."+a.Name]; !ok {
			t.Errorf("no text for the addon %s", a.Name)
		}
	}
}

func TestTFallsBackToEnglish(t *testing.T) {
	if got := T("de", "notfound.title"); got != "Seite nicht gefunden" {
		t.Errorf("T(de) = %q", got)
	}
	if got := T("xx", "notfound.title"); got != "Page not found" {
		t.Errorf("T(unknown language) = %q", got)
	}
	if got := T("de", "no.such.key"); got != "no.such.key" {
		t.Errorf("T(unknown key) = %q", got)
	}
	saved := messages["fr"]["lang.label"]
	delete(messages["fr"], "lang.label")
	defer func() { messages["fr"]["lang.label"] = saved }()
	if got := T("fr", "lang.label"); got != "Language" {
		t.Errorf("T(fr, missing key) = %q, want the English text", got)
	}
}

func TestHomeAndNotFoundInEachLanguage(t *testing.T) {
	s := newSite(t, Options{Name: "My Site", GitHubURL: "https://github.com/a/b"})
	titles := map[Lang]string{"en": "Page not found", "de": "Seite nicht gefunden", "fr": "Page introuvable", "es": "Página no encontrada", "it": "Pagina non trovata", "pt": "Página não encontrada"}
	for _, l := range Langs {
		for name, h := range map[string]http.Handler{"home": s.Home(), "404": s.NotFound()} {
			req := httptest.NewRequest("GET", "/", nil)
			req.AddCookie(&http.Cookie{Name: "lang", Value: string(l)})
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			body := rec.Body.String()
			if !strings.Contains(body, `<html lang="`+string(l)+`">`) {
				t.Errorf("%s %s: no html lang", name, l)
			}
			if got := strings.Count(body, `<a href="?lang=`); got != 6 {
				t.Errorf("%s %s: %d picker links, want 6", name, l, got)
			}
			if strings.Count(body, `aria-current="true"`) != 1 || !strings.Contains(body, `href="?lang=`+string(l)+`" lang="`+string(l)+`" hreflang="`+string(l)+`" aria-current="true"`) {
				t.Errorf("%s %s: the current language is not marked", name, l)
			}
			for _, own := range LangNames {
				if !strings.Contains(body, ">"+own+"</a>") {
					t.Errorf("%s %s: no link named %q", name, l, own)
				}
			}
			if name == "404" && !strings.Contains(body, "<title>"+titles[l]+"</title>") {
				t.Errorf("404 %s: title is not %q", l, titles[l])
			}
			if name == "home" && !strings.Contains(body, "<title>My Site</title>") {
				t.Errorf("home %s: no title", l)
			}
			if rec.Header().Get("Content-Language") != string(l) || rec.Header().Get("Vary") != "Cookie, Accept-Language" {
				t.Errorf("%s %s headers: %v", name, l, rec.Header())
			}
		}
	}
}

func TestHomeUsesTheLanguageOfTheRequest(t *testing.T) {
	s := newSite(t, Options{Name: "X", GitHubURL: "https://github.com/a/b"})
	for name, tc := range map[string]struct {
		cookie, accept, want string
	}{
		"cookie de":     {"de", "", "Was Memories aufzeichnet"},
		"header es":     {"", "es-ES,es;q=0.9", "Lo que registra Memories"},
		"cookie wins":   {"it", "es", "Cosa registra Memories"},
		"nothing":       {"", "", "What Memories records"},
		"unknown":       {"", "ru", "What Memories records"},
		"header pt":     {"", "pt-PT", "O que o Memories registra"},
		"header fr q":   {"", "de;q=0.1, fr", "Ce que Memories enregistre"},
		"bad cookie":    {"xx", "", "What Memories records"},
		"cookie as tag": {"fr-FR", "", "What Memories records"},
	} {
		t.Run(name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/", nil)
			if tc.cookie != "" {
				req.AddCookie(&http.Cookie{Name: "lang", Value: tc.cookie})
			}
			if tc.accept != "" {
				req.Header.Set("Accept-Language", tc.accept)
			}
			rec := httptest.NewRecorder()
			s.Home().ServeHTTP(rec, req)
			if !strings.Contains(rec.Body.String(), tc.want) {
				t.Errorf("home lacks %q", tc.want)
			}
		})
	}
}

func TestHomeStatesTheLanguageCookie(t *testing.T) {
	s := newSite(t, Options{Name: "X"})
	body := serve(t, s.Home(), http.MethodGet).Body.String()
	if !strings.Contains(body, "cookie named lang") {
		t.Error("home does not say that the site keeps the choice in the lang cookie")
	}
}

func TestEnglishHomeKeepsTheTextOfTheAddonTableAndTheSteps(t *testing.T) {
	s := newSite(t, Options{Name: "X"})
	body := serve(t, s.Home(), http.MethodGet).Body.String()
	for _, a := range Addons {
		if !strings.Contains(body, T("en", "addon."+a.Name)) {
			t.Errorf("English home lacks the text of %s", a.Name)
		}
	}
	for _, want := range []string{
		`<code>Interface/AddOns</code>`, `<code>/reload</code>`, "Ask the person who runs this website for an invite code.",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("English home lacks %q", want)
		}
	}
	open := newSite(t, Options{Name: "X", OpenRegistration: true})
	if b := serve(t, open.Home(), http.MethodGet).Body.String(); strings.Contains(b, "invite code") || !strings.Contains(b, "Press Register.") {
		t.Error("open registration home still asks for an invite code")
	}
}
