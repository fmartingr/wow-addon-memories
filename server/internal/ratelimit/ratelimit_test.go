package ratelimit

import (
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type clock struct{ t time.Time }

func (c *clock) Now() time.Time { return c.t }

func newLimiter(limit int64, window time.Duration) (*Limiter, *clock) {
	c := &clock{t: time.Unix(1000, 0)}
	l := New(limit, window)
	l.now = c.Now
	return l, c
}

func TestLimiterWindow(t *testing.T) {
	l, c := newLimiter(3, time.Minute)
	for i := range 3 {
		if ok, _ := l.Allow("k"); !ok {
			t.Fatalf("request %d refused", i+1)
		}
	}
	c.t = c.t.Add(20 * time.Second)
	ok, wait := l.Allow("k")
	if ok || wait != 40*time.Second {
		t.Errorf("4th request = %v, wait %v; want refused with 40s", ok, wait)
	}
	if ok, _ := l.Allow("other"); !ok {
		t.Error("another key shares the window")
	}
	c.t = c.t.Add(40*time.Second - time.Nanosecond)
	if ok, _ := l.Allow("k"); ok {
		t.Error("the window ended too early")
	}
	c.t = c.t.Add(time.Nanosecond)
	if ok, _ := l.Allow("k"); !ok {
		t.Error("the window did not reset")
	}
}

func TestLimiterSweepsEndedWindows(t *testing.T) {
	l, c := newLimiter(1, time.Minute)
	for i := range 100 {
		l.Allow(strconv.Itoa(i))
	}
	if l.Size() != 100 {
		t.Fatalf("Size = %d", l.Size())
	}
	c.t = c.t.Add(2 * time.Minute)
	l.Allow("fresh")
	if l.Size() != 1 {
		t.Errorf("Size = %d after the windows ended, want 1", l.Size())
	}
}

func TestLimiterIsSafeForConcurrentUse(t *testing.T) {
	l := New(50, time.Minute)
	var wg sync.WaitGroup
	var mu sync.Mutex
	allowed := 0
	for range 200 {
		wg.Go(func() {
			if ok, _ := l.Allow("k"); ok {
				mu.Lock()
				allowed++
				mu.Unlock()
			}
		})
	}
	wg.Wait()
	if allowed != 50 {
		t.Errorf("allowed = %d, want 50", allowed)
	}
}

func TestPerIP(t *testing.T) {
	l, _ := newLimiter(2, time.Minute)
	h := PerIP(l, nil, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) }))
	get := func(path, remote string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("GET", path, nil)
		req.RemoteAddr = remote
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec
	}
	if rec := get("/a", "198.51.100.1:1000"); rec.Code != http.StatusNoContent {
		t.Fatalf("status %d", rec.Code)
	}
	if rec := get("/api/v1/info", "198.51.100.1:1000"); rec.Code != http.StatusNoContent {
		t.Fatalf("status %d", rec.Code)
	}
	rec := get("/a", "198.51.100.1:2000")
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") != "60" {
		t.Errorf("status %d, Retry-After %q; want 429 and 60", rec.Code, rec.Header().Get("Retry-After"))
	}
	if body := rec.Body.String(); body == "" || body[0] != 'T' {
		t.Errorf("body = %q, want a plain message", body)
	}
	rec = get("/api/v1/me", "198.51.100.1:1000")
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") != "60" ||
		!strings.Contains(rec.Body.String(), `"error":"rate_limited"`) {
		t.Errorf("API 429 = %d %q %s; want the JSON error with a wait", rec.Code, rec.Header().Get("Retry-After"), rec.Body)
	}
	if rec := get("/a", "198.51.100.2:1000"); rec.Code != http.StatusNoContent {
		t.Errorf("another address got %d", rec.Code)
	}
}

func prefixes(t *testing.T, cidrs ...string) []netip.Prefix {
	t.Helper()
	var out []netip.Prefix
	for _, c := range cidrs {
		out = append(out, netip.MustParsePrefix(c))
	}
	return out
}

func TestClientIP(t *testing.T) {
	proxies := prefixes(t, "10.0.0.0/8", "fd00::/8")
	for _, tc := range []struct {
		name    string
		remote  string
		xff     []string
		trusted []netip.Prefix
		want    string
	}{
		{"no proxies configured", "203.0.113.5:1234", []string{"1.2.3.4"}, nil, "203.0.113.5"},
		{"peer is not a proxy", "203.0.113.5:1234", []string{"1.2.3.4"}, proxies, "203.0.113.5"},
		{"peer is a proxy, one hop", "10.0.0.2:1234", []string{"198.51.100.7"}, proxies, "198.51.100.7"},
		{"the client forges the left side", "10.0.0.2:1234", []string{"1.1.1.1, 198.51.100.7"}, proxies, "198.51.100.7"},
		{"two trusted hops", "10.0.0.2:1234", []string{"198.51.100.7, 10.0.0.9"}, proxies, "198.51.100.7"},
		{"hops split over two header lines", "10.0.0.2:1234", []string{"1.1.1.1", "198.51.100.7, 10.0.0.9"}, proxies, "198.51.100.7"},
		{"an untrusted hop stops the walk", "10.0.0.2:1234", []string{"10.0.0.8, 203.0.113.9, 10.0.0.9"}, proxies, "203.0.113.9"},
		{"no header", "10.0.0.2:1234", nil, proxies, "10.0.0.2"},
		{"only trusted hops", "10.0.0.2:1234", []string{"10.0.0.8, 10.0.0.9"}, proxies, "10.0.0.2"},
		{"a garbage entry", "10.0.0.2:1234", []string{"1.2.3.4, not-an-ip"}, proxies, "10.0.0.2"},
		{"an empty entry", "10.0.0.2:1234", []string{"1.2.3.4,"}, proxies, "10.0.0.2"},
		{"ipv6 client", "10.0.0.2:1234", []string{"2001:db8::1"}, proxies, "2001:db8::1"},
		{"ipv4 hop with a port", "10.0.0.2:1234", []string{"198.51.100.7:5678"}, proxies, "198.51.100.7"},
		{"ipv6 hop with a port", "10.0.0.2:1234", []string{"[2001:db8::1]:5678"}, proxies, "2001:db8::1"},
		{"ipv6 proxy", "[fd00::2]:1234", []string{"198.51.100.7"}, proxies, "198.51.100.7"},
		{"ipv4-mapped peer", "[::ffff:10.0.0.2]:1234", []string{"198.51.100.7"}, proxies, "198.51.100.7"},
		{"remote without a port", "203.0.113.5", nil, proxies, "203.0.113.5"},
		{"remote that is not an address", "pipe", []string{"1.1.1.1"}, proxies, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/", nil)
			req.RemoteAddr = tc.remote
			for _, v := range tc.xff {
				req.Header.Add("X-Forwarded-For", v)
			}
			got := ClientIP(req, tc.trusted)
			if tc.want == "" {
				if got.IsValid() {
					t.Errorf("ClientIP = %v, want invalid", got)
				}
				return
			}
			if got.String() != tc.want {
				t.Errorf("ClientIP = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestIPKey(t *testing.T) {
	for in, want := range map[string]string{
		"203.0.113.5":          "203.0.113.5",
		"2001:db8:1:2::1":      "2001:db8:1:2::/64",
		"2001:db8:1:2:ffff::9": "2001:db8:1:2::/64",
	} {
		if got := IPKey(netip.MustParseAddr(in)); got != want {
			t.Errorf("IPKey(%s) = %s, want %s", in, got, want)
		}
	}
	if got := IPKey(netip.Addr{}); got != "unknown" {
		t.Errorf("IPKey of nothing = %q", got)
	}
}
