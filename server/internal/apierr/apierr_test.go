package apierr

import (
	"bytes"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestWrite(t *testing.T) {
	rec := httptest.NewRecorder()
	Write(rec, http.StatusConflict, "claimed", "Another key owns this path.")
	var got map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if rec.Code != 409 || rec.Header().Get("Content-Type") != "application/json" ||
		got["error"] != "claimed" || got["message"] != "Another key owns this path." || len(got) != 2 {
		t.Errorf("status %d, headers %v, body %v", rec.Code, rec.Header(), got)
	}
}

func TestJSONWithAValueThatCannotBeEncoded(t *testing.T) {
	rec := httptest.NewRecorder()
	JSON(rec, http.StatusOK, make(chan int))
	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status %d, want 500", rec.Code)
	}
}

func TestInternalShowsNoDetail(t *testing.T) {
	rec := httptest.NewRecorder()
	Internal(rec)
	if rec.Code != 500 || !json.Valid(rec.Body.Bytes()) {
		t.Errorf("status %d, body %q", rec.Code, rec.Body)
	}
}

func TestFailLogsTheStepAndHidesTheError(t *testing.T) {
	var out bytes.Buffer
	rec := httptest.NewRecorder()
	Fail(rec, slog.New(slog.NewJSONHandler(&out, nil)), "request failed", "me", errors.New("disk I/O error"))
	if rec.Code != 500 || strings.Contains(rec.Body.String(), "disk") {
		t.Errorf("status %d, body %q; want a 500 without the error", rec.Code, rec.Body)
	}
	if log := out.String(); !strings.Contains(log, `"msg":"request failed"`) || !strings.Contains(log, `"step":"me"`) ||
		!strings.Contains(log, `"err":"disk I/O error"`) {
		t.Errorf("log = %s", log)
	}
}

func TestKeyRevoked(t *testing.T) {
	rec := httptest.NewRecorder()
	KeyRevoked(rec)
	var got map[string]string
	json.Unmarshal(rec.Body.Bytes(), &got)
	if rec.Code != 403 || got["error"] != "key_revoked" || got["message"] == "" {
		t.Errorf("status %d, body %v", rec.Code, got)
	}
}

func TestRetryAfterRoundsUp(t *testing.T) {
	for in, want := range map[time.Duration]string{
		0: "1", time.Nanosecond: "1", time.Second: "1", time.Second + 1: "2", 59500 * time.Millisecond: "60", time.Hour: "3600",
	} {
		if got := RetryAfter(in); got != want {
			t.Errorf("RetryAfter(%v) = %s, want %s", in, got, want)
		}
	}
}

func TestRateLimited(t *testing.T) {
	rec := httptest.NewRecorder()
	RateLimited(rec, 30*time.Second)
	if rec.Code != 429 || rec.Header().Get("Retry-After") != "30" {
		t.Errorf("status %d, Retry-After %q", rec.Code, rec.Header().Get("Retry-After"))
	}
	var got map[string]string
	json.Unmarshal(rec.Body.Bytes(), &got)
	if got["error"] != "rate_limited" || got["message"] == "" {
		t.Errorf("body = %v", got)
	}
}
