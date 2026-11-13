package openreg

import (
	"bytes"
	"context"
	"log/slog"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

func TestLoopClosesOpenRegistrationOnALowDisk(t *testing.T) {
	ctx := context.Background()
	st, err := store.Open(filepath.Join(t.TempDir(), "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	if err := st.SeedOpen(ctx, true); err != nil {
		t.Fatal(err)
	}
	var logs bytes.Buffer
	g := New(st, t.TempDir(), slog.New(slog.NewJSONHandler(&logs, nil)))
	if g.IsOpen() {
		t.Fatal("the gate is open before its first refresh")
	}
	free := make(chan float64, 1)
	free <- 50
	last := 50.0
	g.SetDiskProbe(func(string) (float64, bool) {
		select {
		case last = <-free:
		default:
		}
		return last, true
	})
	if _, err := g.Refresh(ctx); err != nil || !g.IsOpen() {
		t.Fatalf("after a refresh with space: open %v, %v", g.IsOpen(), err)
	}

	loopCtx, stop := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { defer close(done); g.Loop(loopCtx, time.Millisecond) }()
	free <- 5
	deadline := time.Now().Add(5 * time.Second)
	for g.IsOpen() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	stop()
	<-done
	if g.IsOpen() {
		t.Fatal("the loop did not close open registration on a low disk")
	}
	if o, _ := st.OpenSettings(ctx); o.Open {
		t.Error("the stored switch is still on")
	}
	if strings.Count(logs.String(), "open registration is now closed") != 1 {
		t.Errorf("the close is not logged once:\n%s", logs.String())
	}
}
