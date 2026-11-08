package httpserver

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"
)

func freeAddr(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().String()
}

func quietLog() *slog.Logger { return slog.New(slog.NewJSONHandler(io.Discard, nil)) }

func TestRunServesAndStopsOnCancel(t *testing.T) {
	cfg := loadConfig(t, map[string]string{
		"MEMORIES_PUBLIC_ADDR": freeAddr(t),
		"MEMORIES_ADMIN_ADDR":  freeAddr(t),
	})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg, quietLog()) }()

	var resp *http.Response
	var err error
	for range 100 {
		resp, err = http.Get("http://" + cfg.PublicAddr + "/api/v1/info")
		if err == nil {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if err != nil {
		t.Fatalf("the public listener did not start: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("public status = %d", resp.StatusCode)
	}
	admin, err := http.Get("http://" + cfg.AdminAddr + "/")
	if err != nil {
		t.Fatalf("the admin listener did not start: %v", err)
	}
	admin.Body.Close()
	if admin.StatusCode != http.StatusOK || admin.Request.URL.Path != "/requests" {
		t.Errorf("admin / = %d at %s, want the Requests page", admin.StatusCode, admin.Request.URL.Path)
	}

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Errorf("Run = %v, want nil after a clean shutdown", err)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("Run did not return after the context ended")
	}
}

func TestRunReportsABusyPort(t *testing.T) {
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()
	for _, which := range []string{"MEMORIES_PUBLIC_ADDR", "MEMORIES_ADMIN_ADDR"} {
		t.Run(which, func(t *testing.T) {
			env := map[string]string{"MEMORIES_PUBLIC_ADDR": freeAddr(t), "MEMORIES_ADMIN_ADDR": freeAddr(t)}
			env[which] = busy.Addr().String()
			err := Run(context.Background(), loadConfig(t, env), quietLog())
			if err == nil || !strings.Contains(err.Error(), busy.Addr().String()) {
				t.Fatalf("Run = %v, want an error that names %s", err, busy.Addr())
			}
			if !strings.Contains(err.Error(), "no other program uses that port") {
				t.Errorf("Run = %v, want the hint", err)
			}
		})
	}
}

func TestServerTimeouts(t *testing.T) {
	srv := newServer(":0", http.NotFoundHandler(), quietLog())
	got := fmt.Sprint(srv.ReadHeaderTimeout, " ", srv.ReadTimeout, " ", srv.WriteTimeout, " ", srv.IdleTimeout, " ", srv.MaxHeaderBytes)
	if want := "10s 1m0s 1m0s 2m0s 16384"; got != want {
		t.Errorf("timeouts = %s, want %s", got, want)
	}
}

func TestServerErrorsAreJSONLogs(t *testing.T) {
	var logs bytes.Buffer
	srv := newServer(":0", http.NotFoundHandler(), slog.New(slog.NewJSONHandler(&logs, nil)))
	srv.ErrorLog.Print("http: accept error")
	if got := logs.String(); !strings.Contains(got, `"level":"ERROR"`) || !strings.Contains(got, `"msg":"http: accept error"`) {
		t.Errorf("log = %q, want a JSON error line", got)
	}
}
