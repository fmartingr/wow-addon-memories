package main

import (
	"bytes"
	"context"
	"net"
	"strings"
	"testing"
)

func noEnv(string) string { return "" }

func TestRunRejectsAnUnknownCommand(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run(context.Background(), []string{"backup"}, noEnv, &out, &errOut); code != exitUsage {
		t.Errorf("exit code = %d, want %d", code, exitUsage)
	}
	if !strings.Contains(errOut.String(), "usage: memories-server") {
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
	env := func(k string) string {
		switch k {
		case "MEMORIES_PUBLIC_ADDR", "MEMORIES_ADMIN_ADDR":
			return "127.0.0.1:0"
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
	env := func(k string) string {
		switch k {
		case "MEMORIES_PUBLIC_ADDR", "MEMORIES_ADMIN_ADDR":
			return busy.Addr().String()
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
