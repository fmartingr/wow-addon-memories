package reporting

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"
)

type fakeTransport struct {
	mu     sync.Mutex
	events []*sentry.Event
}

func (t *fakeTransport) Flush(time.Duration) bool              { return true }
func (t *fakeTransport) FlushWithContext(context.Context) bool { return true }
func (t *fakeTransport) Configure(sentry.ClientOptions)        {}
func (t *fakeTransport) Close()                                {}
func (t *fakeTransport) SendEvent(e *sentry.Event) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.events = append(t.events, e)
}

func (t *fakeTransport) sent() []*sentry.Event {
	t.mu.Lock()
	defer t.mu.Unlock()
	return slices.Clone(t.events)
}

func setup(t *testing.T) *fakeTransport {
	t.Helper()
	tr := &fakeTransport{}
	err := sentry.Init(sentry.ClientOptions{
		Dsn:              "https://public@sentry.example.com/1",
		Transport:        tr,
		BeforeSend:       scrub,
		AttachStacktrace: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { sentry.CurrentHub().BindClient(nil) })
	return tr
}

func TestInitWithoutDSNDoesNothing(t *testing.T) {
	flush, err := Init(Options{})
	if err != nil {
		t.Fatal(err)
	}
	flush()
}

func TestInitRejectsBadDSN(t *testing.T) {
	if _, err := Init(Options{DSN: "not a dsn"}); err == nil {
		t.Fatal("Init accepted a bad DSN")
	}
}

func TestHandlerSendsErrorsOnly(t *testing.T) {
	tr := setup(t)
	var out bytes.Buffer
	log := slog.New(Handler(slog.NewJSONHandler(&out, nil))).With("component", "api")

	log.Info("listening", "addr", ":8080")
	log.Error("request failed", "step", "save", "err", errors.New("disk full").Error())
	log.Error("http: panic serving 1.2.3.4:5: boom")

	if got := strings.Count(out.String(), "\n"); got != 3 {
		t.Fatalf("the JSON log has %d lines, want 3:\n%s", got, out.String())
	}
	events := tr.sent()
	if len(events) != 1 {
		t.Fatalf("sent %d events, want 1", len(events))
	}
	e := events[0]
	if e.Message != "request failed" || e.Level != sentry.LevelError {
		t.Fatalf("event = %q at %q", e.Message, e.Level)
	}
	if want := []string{"request failed", "step=save"}; !slices.Equal(e.Fingerprint, want) {
		t.Fatalf("fingerprint = %q, want %q", e.Fingerprint, want)
	}
	attrs := e.Contexts["attributes"]
	if attrs["err"] != "disk full" || attrs["component"] != "api" {
		t.Fatalf("attributes = %v", attrs)
	}
}

func TestPanicsReportsWithoutRequestData(t *testing.T) {
	tr := setup(t)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/characters", func(http.ResponseWriter, *http.Request) { panic("boom") })
	h := Panics(mux)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/characters?secret=1", strings.NewReader("body"))
	req.Header.Set("Memories-Signature", "secret")
	func() {
		defer func() {
			if v := recover(); v != "boom" {
				t.Fatalf("recovered %v, want the original panic", v)
			}
		}()
		h.ServeHTTP(httptest.NewRecorder(), req)
	}()

	events := tr.sent()
	if len(events) != 1 {
		t.Fatalf("sent %d events, want 1", len(events))
	}
	e := events[0]
	if e.Request != nil {
		t.Fatalf("the event carries the request: %+v", e.Request)
	}
	if e.Tags["route"] != "POST /api/v1/characters" || e.Tags["method"] != http.MethodPost {
		t.Fatalf("tags = %v", e.Tags)
	}
	if len(e.Threads) == 0 || e.Threads[0].Stacktrace == nil {
		t.Fatal("the event has no stack")
	}
}

func TestPanicsSkipsAbortHandler(t *testing.T) {
	tr := setup(t)
	h := Panics(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { panic(http.ErrAbortHandler) }))
	func() {
		defer func() { recover() }()
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))
	}()
	if n := len(tr.sent()); n != 0 {
		t.Fatalf("sent %d events, want 0", n)
	}
}
