package site

import (
	"strings"
	"testing"
)

func TestCharacterPageCarriesTheLanguageAndItsSource(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `{"name":"Nandu","realm":"brumamar"}`)
	for name, tc := range map[string]struct {
		hdr  []string
		want string
	}{
		"default": {nil, `<html lang="en" data-lang-from="default">`},
		"cookie":  {[]string{"Cookie", "lang=de"}, `<html lang="de" data-lang-from="cookie">`},
		"header":  {[]string{"Accept-Language", "it;q=0.4, fr"}, `<html lang="fr" data-lang-from="header">`},
		"bad":     {[]string{"Cookie", `lang="><script>`}, `<html lang="en" data-lang-from="default">`},
	} {
		t.Run(name, func(t *testing.T) {
			rec := r.get("GET", base+"/", tc.hdr...)
			if !strings.Contains(rec.Body.String(), tc.want) {
				t.Errorf("page lacks %q:\n%.200s", tc.want, rec.Body)
			}
			if rec.Header().Get("Vary") != "Cookie, Accept-Language" {
				t.Errorf("Vary = %q", rec.Header().Get("Vary"))
			}
		})
	}
	a := r.get("GET", base+"/", "Cookie", "lang=de").Header().Get("ETag")
	b := r.get("GET", base+"/", "Cookie", "lang=fr").Header().Get("ETag")
	if a == b {
		t.Error("two languages share one ETag")
	}
}

func TestCharacterPageLanguageKeepsTheTitleAndEntry(t *testing.T) {
	r := newRig(t)
	id := r.claim()
	r.write(id, "character.json", `{"name":"Nandu","realm":"brumamar"}`)
	body := r.get("GET", base+"/", "Cookie", "lang=pt").Body.String()
	for _, want := range []string{"<title>Nandu — brumamar — Memories</title>", `<BODY data-entry="data/entry.json" class="x">`} {
		if !strings.Contains(body, want) {
			t.Errorf("page lacks %q", want)
		}
	}
}
