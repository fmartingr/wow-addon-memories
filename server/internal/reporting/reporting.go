// Package reporting sends the errors of the server and the panics of its handlers to Sentry.
//
// An event carries the log message and its attributes, or the panic value, its stack, the method and the route
// pattern. It never carries a header, a query, a body or the request path, because the Memories-* headers and the
// bodies hold secrets and player data.
package reporting

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/getsentry/sentry-go"
)

const flushTimeout = 2 * time.Second

// Options configures Sentry. An empty DSN turns reporting off.
type Options struct {
	DSN         string
	Environment string
}

// Init starts the Sentry client. It returns a function that sends the queued events; call it before the program ends.
// With an empty DSN, Init does nothing and the returned function does nothing.
func Init(o Options) (flush func(), err error) {
	if o.DSN == "" {
		return func() {}, nil
	}
	err = sentry.Init(sentry.ClientOptions{
		Dsn:         o.DSN,
		Environment: o.Environment,
		// A panic with a string value and a log record have no error with a stack, so the SDK takes the stack here.
		AttachStacktrace: true,
		BeforeSend:       scrub,
	})
	if err != nil {
		return nil, fmt.Errorf("could not start Sentry: %w. Check MEMORIES_SENTRY_DSN", err)
	}
	return func() { sentry.Flush(flushTimeout) }, nil
}

// scrub removes the request and the user from every event, as a guard if an integration of the SDK adds them.
func scrub(event *sentry.Event, _ *sentry.EventHint) *sentry.Event {
	event.Request = nil
	event.User = sentry.User{}
	return event
}

// Panics reports a panic of next to Sentry, then panics again with the same value, so that net/http still logs it
// and closes the connection. http.ErrAbortHandler is not reported, because it is the normal way to abort a response.
func Panics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			v := recover()
			if v == nil {
				return
			}
			if v != http.ErrAbortHandler {
				hub := sentry.CurrentHub().Clone()
				hub.ConfigureScope(func(scope *sentry.Scope) {
					scope.SetTag("method", r.Method)
					// The pattern names the route without the character, which the path holds.
					scope.SetTag("route", r.Pattern)
				})
				hub.RecoverWithContext(r.Context(), v)
			}
			panic(v)
		}()
		next.ServeHTTP(w, r)
	})
}

// groupKeys are the attributes that tell apart two failures with one message, such as the step of "request failed".
var groupKeys = map[string]bool{"step": true, "action": true, "page": true}

// panicPrefix starts the line that net/http logs for a handler panic. Panics already reports that panic with its stack.
const panicPrefix = "http: panic serving"

// Handler returns a slog.Handler that passes every record to next and sends each record at error level or above to
// Sentry. The attributes go to the "attributes" context of the event.
func Handler(next slog.Handler) slog.Handler {
	return &handler{next: next}
}

type handler struct {
	next   slog.Handler
	attrs  []slog.Attr
	prefix string
}

func (h *handler) Enabled(ctx context.Context, level slog.Level) bool {
	return level >= slog.LevelError || h.next.Enabled(ctx, level)
}

func (h *handler) Handle(ctx context.Context, rec slog.Record) error {
	var err error
	if h.next.Enabled(ctx, rec.Level) {
		err = h.next.Handle(ctx, rec)
	}
	if rec.Level >= slog.LevelError && !strings.HasPrefix(rec.Message, panicPrefix) {
		h.send(rec)
	}
	return err
}

func (h *handler) send(rec slog.Record) {
	event := sentry.NewEvent()
	event.Level = sentry.LevelError
	event.Message = rec.Message
	event.Logger = "slog"
	event.Timestamp = rec.Time
	attrs := sentry.Context{}
	event.Fingerprint = []string{rec.Message}
	event.Threads = []sentry.Thread{{Stacktrace: sentry.NewStacktrace(), Current: true}}
	add := func(prefix string, a slog.Attr) {
		key := prefix + a.Key
		val := a.Value.Resolve().String()
		attrs[key] = val
		if groupKeys[key] {
			event.Fingerprint = append(event.Fingerprint, key+"="+val)
		}
	}
	for _, a := range h.attrs {
		add("", a)
	}
	rec.Attrs(func(a slog.Attr) bool {
		add(h.prefix, a)
		return true
	})
	event.Contexts = map[string]sentry.Context{"attributes": attrs}
	sentry.CurrentHub().CaptureEvent(event)
}

func (h *handler) WithAttrs(attrs []slog.Attr) slog.Handler {
	next := &handler{next: h.next.WithAttrs(attrs), prefix: h.prefix}
	next.attrs = append(next.attrs, h.attrs...)
	for _, a := range attrs {
		next.attrs = append(next.attrs, slog.Attr{Key: h.prefix + a.Key, Value: a.Value})
	}
	return next
}

func (h *handler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	return &handler{next: h.next.WithGroup(name), attrs: h.attrs, prefix: h.prefix + name + "."}
}
