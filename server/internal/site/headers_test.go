package site

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHeadersSetOnEveryStatus(t *testing.T) {
	for _, status := range []int{http.StatusOK, http.StatusNotFound, http.StatusInternalServerError, http.StatusFound} {
		h := Headers(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(status) }))
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
		want := map[string]string{
			"X-Content-Type-Options":  "nosniff",
			"Referrer-Policy":         "no-referrer",
			"X-Frame-Options":         "DENY",
			"Content-Security-Policy": contentSecurityPolicy,
		}
		for name, v := range want {
			if got := rec.Header().Get(name); got != v {
				t.Errorf("status %d: %s = %q, want %q", status, name, got, v)
			}
		}
		if rec.Code != status {
			t.Errorf("status = %d, want %d", rec.Code, status)
		}
	}
}
