package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestSignedRequestRules(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open"})
	c := newClient(1)
	e.registered2(c)

	t.Run("a replayed request is refused", func(t *testing.T) {
		req := e.request(c, "GET", "/api/v1/me", "")
		if rec := e.serve(req); rec.Code != http.StatusOK {
			t.Fatalf("first: %d", rec.Code)
		}
		again := e.request(c, "GET", "/api/v1/me", "", signOpts{nonce: nonceOf(t, req)})
		expectError(t, e.serve(again), http.StatusUnauthorized, "bad_signature")
	})

	t.Run("a replayed registration is refused", func(t *testing.T) {
		d := newClient(2)
		req := e.request(d, "POST", "/api/v1/register", "{}")
		if rec := e.serve(req); rec.Code != http.StatusCreated {
			t.Fatalf("first: %d", rec.Code)
		}
		again := e.request(d, "POST", "/api/v1/register", "{}", signOpts{nonce: nonceOf(t, req)})
		expectError(t, e.serve(again), http.StatusUnauthorized, "bad_signature")
	})

	t.Run("a nonce of another key is accepted", func(t *testing.T) {
		d := newClient(3)
		e.registered2(d)
		shared := make([]byte, 16)
		shared[0] = 9
		if rec := e.serve(e.request(c, "GET", "/api/v1/me", "", signOpts{nonce: shared})); rec.Code != http.StatusOK {
			t.Fatalf("first key: %d", rec.Code)
		}
		if rec := e.serve(e.request(d, "GET", "/api/v1/me", "", signOpts{nonce: shared})); rec.Code != http.StatusOK {
			t.Errorf("second key: %d", rec.Code)
		}
	})

	t.Run("time window", func(t *testing.T) {
		now := e.clock.Now().Unix()
		for _, tc := range []struct {
			offset int64
			status int
		}{{-300, 200}, {300, 200}, {-301, 401}, {301, 401}} {
			rec := e.serve(e.request(c, "GET", "/api/v1/me", "", signOpts{time: now + tc.offset}))
			if rec.Code != tc.status {
				t.Errorf("offset %d: status %d, want %d", tc.offset, rec.Code, tc.status)
			}
			if tc.status == 401 {
				a := expectError(t, rec, 401, "bad_signature")
				if !strings.Contains(a.Message, "clock") {
					t.Errorf("message %q does not mention the clock", a.Message)
				}
			}
		}
	})

	t.Run("a wrong signature", func(t *testing.T) {
		req := e.request(c, "GET", "/api/v1/me", "")
		req.RequestURI = "/api/v1/me?x=1"
		expectError(t, e.serve(req), http.StatusUnauthorized, "bad_signature")
	})

	t.Run("a missing header", func(t *testing.T) {
		for _, h := range []string{"Memories-Key", "Memories-Time", "Memories-Nonce", "Memories-Signature"} {
			req := e.request(c, "GET", "/api/v1/me", "")
			req.Header.Del(h)
			expectError(t, e.serve(req), http.StatusUnauthorized, "bad_signature")
		}
	})

	t.Run("a request with no signature", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/api/v1/me", nil)
		expectError(t, e.serve(req), http.StatusUnauthorized, "bad_signature")
	})

	t.Run("a body that differs from the signed body", func(t *testing.T) {
		req := e.request(c, "POST", "/api/v1/screenshots/request", "")
		req.Body = httptest.NewRequest("POST", "/", strings.NewReader("tampered")).Body
		expectError(t, e.serve(req), http.StatusUnauthorized, "bad_signature")
	})
}

func TestReplayIsRefusedAfterARestart(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open"})
	c := newClient(1)
	e.registered2(c)
	req := e.request(c, "GET", "/api/v1/me", "")
	if rec := e.serve(req); rec.Code != http.StatusOK {
		t.Fatal(rec.Code)
	}
	e.st.Close()
	e.start()
	again := e.request(c, "GET", "/api/v1/me", "", signOpts{nonce: nonceOf(t, req)})
	expectError(t, e.serve(again), http.StatusUnauthorized, "bad_signature")
}

func TestUnregisteredKeyIsRefused(t *testing.T) {
	e := newEnv(t, nil)
	c := newClient(1)
	for _, tc := range []struct{ method, path string }{{"GET", "/api/v1/me"}, {"POST", "/api/v1/screenshots/request"}} {
		expectError(t, e.do(c, tc.method, tc.path, ""), http.StatusUnauthorized, "not_registered")
	}
}

func TestRevokedKeyIsRefusedEverywhere(t *testing.T) {
	e := newEnv(t, nil)
	c := newClient(1)
	e.registered(c)
	e.revoke(c)
	for _, tc := range []struct{ method, path, body string }{
		{"GET", "/api/v1/me", ""},
		{"POST", "/api/v1/screenshots/request", ""},
		{"POST", "/api/v1/register", "{}"},
	} {
		expectError(t, e.do(c, tc.method, tc.path, tc.body), http.StatusForbidden, "key_revoked")
	}
}

func TestSignedRateLimitPerKey(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_RATE_SIGNED_PER_MINUTE": "3"})
	a, b := newClient(1), newClient(2)
	e.registered2(a)
	e.registered2(b)
	for i := range 3 {
		if rec := e.do(a, "GET", "/api/v1/me", ""); rec.Code != http.StatusOK {
			t.Fatalf("request %d: %d", i+1, rec.Code)
		}
	}
	rec := e.do(a, "GET", "/api/v1/me", "")
	expectError(t, rec, http.StatusTooManyRequests, "rate_limited")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("no Retry-After header")
	}
	if rec := e.do(b, "GET", "/api/v1/me", ""); rec.Code != http.StatusOK {
		t.Errorf("another key shares the limit: %d", rec.Code)
	}
}

func TestSignedBodyLimit(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open"})
	c := newClient(1)
	e.registered2(c)
	expectError(t, e.do(c, "POST", "/api/v1/screenshots/request", strings.Repeat("x", 2048)),
		http.StatusRequestEntityTooLarge, "too_large")
}

func TestMe(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_SITE_URL": "https://journey.example"})
	c := newClient(1)
	e.registered(c)

	a := decode(t, e.do(c, "GET", "/api/v1/me", ""))
	if a.Screenshots != "none" || a.Characters == nil || len(a.Characters) != 0 {
		t.Errorf("a new key: %+v", a)
	}
	if body := e.do(c, "GET", "/api/v1/me", "").Body.String(); !strings.Contains(body, `"characters":[]`) {
		t.Errorf("body = %s, want an empty list and not null", body)
	}

	k, _ := e.st.KeyByPublic(bg, c.public())
	other := newClient(2)
	e.registered(other)
	ok, _ := e.st.KeyByPublic(bg, other.public())
	for _, claim := range []struct {
		realm, name string
		key         int64
		steps       int64
	}{{"brumamar", "nandu", k.ID, 15}, {"zul", "bob", k.ID, 2}, {"zul", "eve", ok.ID, 1}} {
		if _, err := e.st.CreateClaim(bg, claimOf(claim.realm, claim.name, claim.key, claim.steps)); err != nil {
			t.Fatal(err)
		}
	}
	e.st.SetScreenshots(bg, k.ID, "approved")

	a = decode(t, e.do(c, "GET", "/api/v1/me", ""))
	if a.Screenshots != "approved" || len(a.Characters) != 2 {
		t.Fatalf("answer = %+v", a)
	}
	first := a.Characters[0]
	if first.Path != "wow/eu/brumamar/nandu" || first.URL != "https://journey.example/wow/eu/brumamar/nandu/" ||
		first.GUID != "Player-1-0000000F" || first.Steps != 15 || first.Updated != e.clock.Now().Unix() {
		t.Errorf("first character = %+v", first)
	}
}

func TestMeUpdatesLastSeen(t *testing.T) {
	e := newEnv(t, nil)
	c := newClient(1)
	e.registered(c)
	e.clock.Advance(2 * time.Minute)
	e.do(c, "GET", "/api/v1/me", "")
	k, _ := e.st.KeyByPublic(bg, c.public())
	if k.LastSeen != e.clock.Now().Unix() {
		t.Errorf("LastSeen = %d, want %d", k.LastSeen, e.clock.Now().Unix())
	}
}

func TestScreenshotsRequest(t *testing.T) {
	e := newEnv(t, nil)
	c := newClient(1)
	e.registered(c)
	k, _ := e.st.KeyByPublic(bg, c.public())
	for _, tc := range []struct{ from, want string }{
		{"none", "pending"}, {"pending", "pending"}, {"approved", "approved"}, {"denied", "pending"},
	} {
		e.st.SetScreenshots(bg, k.ID, tc.from)
		rec := e.do(c, "POST", "/api/v1/screenshots/request", "")
		if got := decode(t, rec); rec.Code != http.StatusOK || got.Screenshots != tc.want {
			t.Errorf("from %s: %d %q, want 200 %q", tc.from, rec.Code, got.Screenshots, tc.want)
		}
		if after, _ := e.st.KeyByPublic(bg, c.public()); after.Screenshots != tc.want {
			t.Errorf("from %s: stored %q, want %q", tc.from, after.Screenshots, tc.want)
		}
	}
}

func TestInternalErrorsLeakNothing(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open"})
	c := newClient(1)
	e.registered2(c)
	e.st.Close()

	for _, tc := range []struct{ method, path, body string }{
		{"GET", "/api/v1/me", ""},
		{"POST", "/api/v1/register", `{"invite":"SECRETCODE12345X"}`},
	} {
		rec := e.do(c, tc.method, tc.path, tc.body)
		a := expectError(t, rec, http.StatusInternalServerError, "internal")
		if strings.Contains(a.Message, "sql") || strings.Contains(a.Message, "database") {
			t.Errorf("message %q shows internals", a.Message)
		}
	}
	logs := e.logs.String()
	if !strings.Contains(logs, "auth failed") {
		t.Errorf("the failure was not logged: %q", logs)
	}
	for _, secret := range []string{base64Raw(c.public()), "SECRETCODE12345X", "Memories-"} {
		if strings.Contains(logs, secret) {
			t.Errorf("the log holds %q", secret)
		}
	}
}
