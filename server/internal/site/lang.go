package site

import (
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// Lang is the code of a page language.
type Lang string

// Langs lists the 6 page languages. The first one is the fallback.
var Langs = []Lang{"en", "de", "fr", "es", "it", "pt"}

// LangNames gives each language its own name, for the picker.
var LangNames = map[Lang]string{
	"en": "English", "de": "Deutsch", "fr": "Français", "es": "Español", "it": "Italiano", "pt": "Português",
}

const (
	langCookie    = "lang"
	langMaxAge    = 31536000
	maxAcceptLang = 1024

	FromQuery   = "query"
	FromCookie  = "cookie"
	FromHeader  = "header"
	FromDefault = "default"
)

// wowLocales are the values of GetLocale() that the addons write to character.json.
var wowLocales = map[string]Lang{
	"enUS": "en", "enGB": "en", "deDE": "de", "frFR": "fr", "esES": "es", "esMX": "es", "itIT": "it", "ptBR": "pt", "ptPT": "pt",
}

// code returns s when it is exactly one of the 6 codes.
func code(s string) (Lang, bool) {
	for _, l := range Langs {
		if string(l) == s {
			return l, true
		}
	}
	return "", false
}

// FromTag maps a BCP 47 tag (primary subtag only) or a WoW locale to a language.
func FromTag(tag string) (Lang, bool) {
	tag = strings.TrimSpace(tag)
	if l, ok := wowLocales[tag]; ok {
		return l, true
	}
	primary, rest, hasRest := strings.Cut(strings.ReplaceAll(strings.ToLower(tag), "_", "-"), "-")
	if hasRest && rest == "" {
		return "", false
	}
	return code(primary)
}

// Pick chooses the page language from the request and says where it came from: the lang query, the lang cookie, the
// Accept-Language header or the default. A value that is not one of the 6 codes goes to the next step.
func Pick(r *http.Request) (Lang, string) {
	if v := r.URL.Query()["lang"]; len(v) > 0 {
		if l, ok := code(v[0]); ok {
			return l, FromQuery
		}
	}
	if c, err := r.Cookie(langCookie); err == nil {
		if l, ok := code(c.Value); ok {
			return l, FromCookie
		}
	}
	if l, ok := fromAccept(r.Header.Get("Accept-Language")); ok {
		return l, FromHeader
	}
	return Langs[0], FromDefault
}

// fromAccept returns the language with the highest q that FromTag maps. The first one wins a tie. Parts that do not
// parse are ignored, and only the whole parts of the first 1 KiB are read.
func fromAccept(header string) (Lang, bool) {
	if len(header) > maxAcceptLang {
		// The cut can fall inside a part, and a part cut before its ";q=" would count as q=1.
		header = header[:max(strings.LastIndexByte(header[:maxAcceptLang], ','), 0)]
	}
	var best Lang
	bestQ := 0.0
	for part := range strings.SplitSeq(header, ",") {
		tag, params, _ := strings.Cut(part, ";")
		q, ok := weight(params)
		if !ok {
			continue
		}
		l, ok := FromTag(tag)
		if ok && q > bestQ {
			best, bestQ = l, q
		}
	}
	return best, bestQ > 0
}

// weight returns the q parameter of the ";"-separated params of one Accept-Language part, 1 when there is none. The
// name is case-insensitive (RFC 9110 12.4.2) and other parameters are skipped. A q that does not parse or is above 1
// makes the part malformed.
func weight(params string) (float64, bool) {
	for p := range strings.SplitSeq(params, ";") {
		name, val, ok := strings.Cut(strings.TrimSpace(p), "=")
		if !ok || !strings.EqualFold(strings.TrimSpace(name), "q") {
			continue
		}
		q, err := strconv.ParseFloat(strings.TrimSpace(val), 64)
		return q, err == nil && q <= 1
	}
	return 1, true
}

// LangChoice handles the language picker links. A GET or HEAD request with a lang query sets the lang cookie when the
// first value is one of the 6 codes, and answers 303 See Other to the same URL without lang. The API, the viewer files
// and the data files of a character ignore the query. secure marks the cookie Secure for a site behind TLS.
func LangChoice(secure bool, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		values := r.URL.Query()["lang"]
		if (r.Method != http.MethodGet && r.Method != http.MethodHead) || len(values) == 0 || ignoresLang(r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}
		if l, ok := code(values[0]); ok {
			http.SetCookie(w, &http.Cookie{
				Name: langCookie, Value: string(l), Path: "/", MaxAge: langMaxAge, SameSite: http.SameSiteLaxMode,
				Secure: secure || r.TLS != nil,
			})
		}
		// Leading slashes would turn the Location into a link to another host.
		location := "/" + strings.TrimLeft(r.URL.EscapedPath(), "/")
		if rest := withoutLang(r.URL.RawQuery); rest != "" {
			location += "?" + rest
		}
		w.Header().Set("Location", location)
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(http.StatusSeeOther)
	})
}

func ignoresLang(path string) bool {
	if strings.HasPrefix(path, "/api/") || strings.HasPrefix(path, AssetPrefix) {
		return true
	}
	parts := strings.Split(strings.Trim(path, "/"), "/")
	return len(parts) >= 5 && parts[4] == "data"
}

// withoutLang drops every lang pair of a raw query and keeps the order of the others.
func withoutLang(raw string) string {
	var keep []string
	for pair := range strings.SplitSeq(raw, "&") {
		key, _, _ := strings.Cut(pair, "=")
		if k, err := url.QueryUnescape(key); pair != "" && (err != nil || k != "lang") {
			keep = append(keep, pair)
		}
	}
	return strings.Join(keep, "&")
}
