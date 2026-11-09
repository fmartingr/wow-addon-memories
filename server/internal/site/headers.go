package site

import "net/http"

const framePolicy = "frame-ancestors 'none'; base-uri 'none'; form-action 'self'"

const contentSecurityPolicy = "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; " + framePolicy

// characterPagePolicy is the policy of a character page. It adds the hosts of the Wowhead tooltip script, which names
// the gear. They are the hosts that the script uses in the browser: the script, its style sheet and the item icons
// come from wow.zamimg.com, and the item data comes from nether.wowhead.com. The tooltip needs no inline style.
const characterPagePolicy = "default-src 'self'; img-src 'self' data: https://wow.zamimg.com; " +
	"script-src 'self' https://wow.zamimg.com https://nether.wowhead.com; style-src 'self' https://wow.zamimg.com; " +
	"connect-src 'self' https://nether.wowhead.com; " + framePolicy

// Headers sets the security headers on every response, including redirects and errors.
func Headers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Content-Security-Policy", contentSecurityPolicy)
		next.ServeHTTP(w, r)
	})
}
