package api

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestRegisterInInviteMode(t *testing.T) {
	e := newEnv(t, nil)
	c := newClient(1)
	code := e.invite()

	rec := e.register(c, code)
	if rec.Code != http.StatusCreated || !decode(t, rec).Registered {
		t.Fatalf("first registration: %d %s", rec.Code, rec.Body)
	}
	rec = e.register(c, "ignored")
	if rec.Code != http.StatusOK || !decode(t, rec).Registered {
		t.Errorf("second registration of the same key: %d %s", rec.Code, rec.Body)
	}
	if k, err := e.st.KeyByPublic(bg, c.public()); err != nil || k.Screenshots != "none" {
		t.Errorf("stored key = %+v, %v", k, err)
	}
}

func TestRegisterInviteErrors(t *testing.T) {
	e := newEnv(t, nil)
	used := e.invite()
	e.register(newClient(1), used)
	expiredID, expired, _ := e.st.CreateInvite(bg, "", -time.Hour)
	_ = expiredID
	revokedID, revoked, _ := e.st.CreateInvite(bg, "", time.Hour)
	e.st.RevokeInvite(bg, revokedID)

	for name, body := range map[string]string{
		"no code":        `{}`,
		"empty code":     `{"invite":""}`,
		"unknown code":   `{"invite":"0123456789ABCDEF"}`,
		"code of a key":  `{"invite":"` + used + `"}`,
		"expired code":   `{"invite":"` + expired + `"}`,
		"revoked code":   `{"invite":"` + revoked + `"}`,
		"malformed code": `{"invite":"short"}`,
	} {
		t.Run(name, func(t *testing.T) {
			a := expectError(t, e.do(newClient(2), "POST", "/api/v1/register", body), http.StatusForbidden, "invite_invalid")
			if !strings.Contains(a.Message, "Ask the website admin") {
				t.Errorf("message %q does not say what to do", a.Message)
			}
		})
	}
	if _, err := e.st.KeyByPublic(bg, newClient(2).public()); err == nil {
		t.Error("a failed registration left a key")
	}
}

func TestRegisterInOpenMode(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open"})
	for i, body := range []string{`{}`, `{"invite":"garbage"}`} {
		rec := e.do(newClient(byte(i+1)), "POST", "/api/v1/register", body)
		if rec.Code != http.StatusCreated {
			t.Errorf("open registration with %s: %d %s", body, rec.Code, rec.Body)
		}
	}
}

func TestRegisterBadBodies(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open"})
	for name, body := range map[string]string{
		"empty":           ``,
		"not json":        `nope`,
		"an array":        `[]`,
		"unknown field":   `{"invite":"x","admin":true}`,
		"wrong type":      `{"invite":5}`,
		"trailing object": `{}{}`,
		"trailing text":   `{} x`,
		"trailing brace":  "{}}",
		"trailing array":  `{"invite":"X"}]`,
	} {
		t.Run(name, func(t *testing.T) {
			expectError(t, e.do(newClient(1), "POST", "/api/v1/register", body), http.StatusBadRequest, "bad_request")
		})
	}
	if _, err := e.st.KeyByPublic(bg, newClient(1).public()); err == nil {
		t.Error("a bad body registered the key")
	}
}

func TestRegisterBodyLimit(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open"})
	ok := `{"invite":"` + strings.Repeat("a", 1024-13) + `"}`
	if len(ok) != 1024 {
		t.Fatalf("test body is %d bytes", len(ok))
	}
	if rec := e.do(newClient(1), "POST", "/api/v1/register", ok); rec.Code != http.StatusCreated {
		t.Errorf("a body of 1 KiB: %d %s", rec.Code, rec.Body)
	}
	big := `{"invite":"` + strings.Repeat("a", 1024-12) + `"}`
	expectError(t, e.do(newClient(2), "POST", "/api/v1/register", big), http.StatusRequestEntityTooLarge, "too_large")
}

func TestRevokedKeyCannotRegisterAndKeepsTheInvite(t *testing.T) {
	e := newEnv(t, nil)
	c := newClient(1)
	e.registered(c)
	e.revoke(c)
	code := e.invite()
	expectError(t, e.register(c, code), http.StatusForbidden, "key_revoked")
	if rec := e.register(newClient(2), code); rec.Code != http.StatusCreated {
		t.Errorf("the invite was spent by the revoked key: %d %s", rec.Code, rec.Body)
	}
}

func TestRegisterRateLimitPerIP(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_RATE_REGISTER_PER_HOUR": "3"})
	for i := range 3 {
		c := newClient(byte(i + 1))
		c.ip = "198.51.100.9"
		if rec := e.register(c, ""); rec.Code != http.StatusCreated {
			t.Fatalf("registration %d: %d", i+1, rec.Code)
		}
	}
	c := newClient(10)
	c.ip = "198.51.100.9"
	rec := e.register(c, "")
	expectError(t, rec, http.StatusTooManyRequests, "rate_limited")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("no Retry-After header")
	}
	other := newClient(11)
	other.ip = "198.51.100.10"
	if rec := e.register(other, ""); rec.Code != http.StatusCreated {
		t.Errorf("another address: %d", rec.Code)
	}
}

func TestRegisterRateLimitCountsFailuresToo(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_RATE_REGISTER_PER_HOUR": "2"})
	for range 2 {
		expectError(t, e.register(newClient(1), "0123456789ABCDEF"), http.StatusForbidden, "invite_invalid")
	}
	expectError(t, e.register(newClient(1), e.invite()), http.StatusTooManyRequests, "rate_limited")
}

func TestRegisterIPFollowsTrustedProxiesOnly(t *testing.T) {
	vars := map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_RATE_REGISTER_PER_HOUR": "1", "MEMORIES_TRUSTED_PROXIES": "10.0.0.0/8"}

	t.Run("behind a trusted proxy each client has its own limit", func(t *testing.T) {
		e := newEnv(t, vars)
		for i, xff := range []string{"203.0.113.1", "203.0.113.2"} {
			c := newClient(byte(i + 1))
			c.ip, c.xff = "10.0.0.5", xff
			if rec := e.register(c, ""); rec.Code != http.StatusCreated {
				t.Errorf("client %s: %d", xff, rec.Code)
			}
		}
		c := newClient(3)
		c.ip, c.xff = "10.0.0.5", "203.0.113.1"
		expectError(t, e.register(c, ""), http.StatusTooManyRequests, "rate_limited")
	})

	t.Run("a header from an untrusted peer is ignored", func(t *testing.T) {
		e := newEnv(t, vars)
		a := newClient(1)
		a.ip, a.xff = "192.0.2.50", "203.0.113.1"
		if rec := e.register(a, ""); rec.Code != http.StatusCreated {
			t.Fatalf("first: %d", rec.Code)
		}
		b := newClient(2)
		b.ip, b.xff = "192.0.2.50", "203.0.113.2"
		expectError(t, e.register(b, ""), http.StatusTooManyRequests, "rate_limited")
	})

	t.Run("a forged left side does not give a new limit", func(t *testing.T) {
		e := newEnv(t, vars)
		a := newClient(1)
		a.ip, a.xff = "10.0.0.5", "1.1.1.1, 203.0.113.1"
		e.register(a, "")
		b := newClient(2)
		b.ip, b.xff = "10.0.0.5", "2.2.2.2, 203.0.113.1"
		expectError(t, e.register(b, ""), http.StatusTooManyRequests, "rate_limited")
	})

	t.Run("no trusted proxy, every client behind one proxy shares the limit", func(t *testing.T) {
		vars := map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_RATE_REGISTER_PER_HOUR": "1"}
		e := newEnv(t, vars)
		a := newClient(1)
		a.ip, a.xff = "10.0.0.5", "203.0.113.1"
		e.register(a, "")
		b := newClient(2)
		b.ip, b.xff = "10.0.0.5", "203.0.113.2"
		expectError(t, e.register(b, ""), http.StatusTooManyRequests, "rate_limited")
	})
}
