package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunWritesTheCatalog(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "kinds.md")
	dst := filepath.Join(dir, "kinds.json")
	md := "## Memories\n| `in` | Sessions | Login | `how`, `#n` |\n"
	if err := os.WriteFile(src, []byte(md), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := run(src, dst); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatal(err)
	}
	want := "{\n  \"in\": {\n    \"addon\": \"Memories\",\n    \"fields\": {\n      \"how\": \"text\",\n      \"n\": \"number\"\n    }\n  }\n}\n"
	if !bytes.Equal(got, []byte(want)) {
		t.Errorf("kinds.json = %q, want %q", got, want)
	}
}

func TestRunErrors(t *testing.T) {
	dir := t.TempDir()
	if err := run(filepath.Join(dir, "missing.md"), filepath.Join(dir, "out.json")); err == nil {
		t.Error("a missing source gave no error")
	}
	empty := filepath.Join(dir, "empty.md")
	if err := os.WriteFile(empty, []byte("# nothing\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := run(empty, filepath.Join(dir, "out.json"))
	if err == nil || !strings.Contains(err.Error(), "empty.md") {
		t.Errorf("err = %v, want it to name the source file", err)
	}
}
