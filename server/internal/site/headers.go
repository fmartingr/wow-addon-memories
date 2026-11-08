package site

import "net/http"

const contentSecurityPolicy = "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; " +
	"frame-ancestors 'none'; base-uri 'none'; form-action 'self'"

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
