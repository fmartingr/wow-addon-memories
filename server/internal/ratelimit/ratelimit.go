// Package ratelimit counts requests in fixed windows and finds the client address behind a trusted proxy.
package ratelimit

import (
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
)

type bucket struct {
	start time.Time
	count int64
}

// Limiter is an in-memory fixed-window counter keyed by a string. A window starts with the first request of its key.
type Limiter struct {
	limit  int64
	window time.Duration
	now    func() time.Time

	mu        sync.Mutex
	buckets   map[string]*bucket
	lastSweep time.Time
}

// New returns a Limiter that allows limit requests per key in each window.
func New(limit int64, window time.Duration) *Limiter {
	return &Limiter{limit: limit, window: window, now: time.Now, buckets: map[string]*bucket{}}
}

// Allow counts one request of key. When the window of key is full it returns false and the time until the window ends.
func (l *Limiter) Allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	l.sweep(now)
	b := l.buckets[key]
	if b == nil || !now.Before(b.start.Add(l.window)) {
		b = &bucket{start: now}
		l.buckets[key] = b
	}
	if b.count >= l.limit {
		return false, b.start.Add(l.window).Sub(now)
	}
	b.count++
	return true, 0
}

// sweep drops the windows that ended, at most once per window, so that the map holds only the keys seen recently.
func (l *Limiter) sweep(now time.Time) {
	if now.Sub(l.lastSweep) < l.window {
		return
	}
	l.lastSweep = now
	for k, b := range l.buckets {
		if !now.Before(b.start.Add(l.window)) {
			delete(l.buckets, k)
		}
	}
}

// Size returns the number of keys the Limiter holds. It exists for tests.
func (l *Limiter) Size() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.buckets)
}

// PerIP limits every request by client address. A refused request under /api/ gets the JSON error of the API, any
// other a plain-text 429.
func PerIP(l *Limiter, trusted []netip.Prefix, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ok, wait := l.Allow(IPKey(ClientIP(r, trusted)))
		switch {
		case ok:
			next.ServeHTTP(w, r)
		case strings.HasPrefix(r.URL.Path, "/api/"):
			apierr.RateLimited(w, wait)
		default:
			secs := apierr.RetryAfter(wait)
			w.Header().Set("Retry-After", secs)
			http.Error(w, "Too many requests. Wait "+secs+" seconds, then try again.", http.StatusTooManyRequests)
		}
	})
}
