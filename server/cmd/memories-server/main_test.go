package main

import (
	"bytes"
	"context"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

func noEnv(string) string { return "" }

func TestRunRejectsAnUnknownCommand(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run(context.Background(), []string{"restore"}, noEnv, &out, &errOut); code != exitUsage {
		t.Errorf("exit code = %d, want %d", code, exitUsage)
	}
	if !strings.Contains(errOut.String(), "usage: memories-server") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

func TestRunBackupNeedsOneFolder(t *testing.T) {
	for _, args := range [][]string{{"backup"}, {"backup", "a", "b"}} {
		var out, errOut bytes.Buffer
		if code := run(context.Background(), args, noEnv, &out, &errOut); code != exitUsage {
			t.Errorf("%v: exit code = %d, want %d", args, code, exitUsage)
		}
		if !strings.Contains(errOut.String(), "memories-server backup <new folder>") {
			t.Errorf("%v: stderr = %q", args, errOut.String())
		}
	}
}

func TestRunBackupWritesTheFolderAndRefusesAnExistingOne(t *testing.T) {
	data := t.TempDir()
	st, err := store.Open(filepath.Join(data, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	st.Close()
	env := func(k string) string {
		if k == "MEMORIES_DATA_DIR" {
			return data
		}
		return ""
	}
	dest := filepath.Join(t.TempDir(), "backup")

	var out, errOut bytes.Buffer
	if code := run(context.Background(), []string{"backup", dest}, env, &out, &errOut); code != exitOK {
		t.Fatalf("exit code = %d, stderr %q", code, errOut.String())
	}
	if !strings.Contains(out.String(), "Backup written to "+dest) {
		t.Errorf("stdout = %q", out.String())
	}
	if _, err := os.Stat(filepath.Join(dest, "memories.db")); err != nil {
		t.Error(err)
	}

	out.Reset()
	errOut.Reset()
	if code := run(context.Background(), []string{"backup", dest}, env, &out, &errOut); code != exitError {
		t.Errorf("second backup: exit code = %d, want %d", code, exitError)
	}
	if !strings.Contains(errOut.String(), "already exists") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

func TestRunRejectsExtraArguments(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run(context.Background(), []string{"serve", "now"}, noEnv, &out, &errOut); code != exitUsage {
		t.Errorf("exit code = %d, want %d", code, exitUsage)
	}
}

func TestRunExitsWithCode2OnABadSetting(t *testing.T) {
	var out, errOut bytes.Buffer
	env := func(k string) string {
		if k == "MEMORIES_REGISTRATION" {
			return "closed"
		}
		return ""
	}
	if code := run(context.Background(), nil, env, &out, &errOut); code != exitUsage {
		t.Errorf("exit code = %d, want %d", code, exitUsage)
	}
	if !strings.Contains(errOut.String(), "MEMORIES_REGISTRATION") {
		t.Errorf("stderr = %q, want the variable named", errOut.String())
	}
}

func TestRunServeStopsOnCancel(t *testing.T) {
	var out, errOut bytes.Buffer
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	dir := t.TempDir()
	env := func(k string) string {
		switch k {
		case "MEMORIES_PUBLIC_ADDR", "MEMORIES_ADMIN_ADDR":
			return "127.0.0.1:0"
		case "MEMORIES_DATA_DIR":
			return dir
		case "MEMORIES_WEB_DIR":
			return "../../../web"
		}
		return ""
	}
	if code := run(ctx, []string{"serve"}, env, &out, &errOut); code != exitOK {
		t.Errorf("exit code = %d, stderr %q", code, errOut.String())
	}
	if !strings.Contains(out.String(), `"msg":"listening"`) {
		t.Errorf("stdout = %q, want JSON log lines", out.String())
	}
}

func TestRunReportsAListenFailureWithExit1(t *testing.T) {
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()
	var out, errOut bytes.Buffer
	dir := t.TempDir()
	env := func(k string) string {
		switch k {
		case "MEMORIES_PUBLIC_ADDR", "MEMORIES_ADMIN_ADDR":
			return busy.Addr().String()
		case "MEMORIES_DATA_DIR":
			return dir
		case "MEMORIES_WEB_DIR":
			return "../../../web"
		}
		return ""
	}
	if code := run(context.Background(), nil, env, &out, &errOut); code != exitError {
		t.Errorf("exit code = %d, want %d", code, exitError)
	}
	if errOut.Len() == 0 {
		t.Error("stderr is empty")
	}
}
