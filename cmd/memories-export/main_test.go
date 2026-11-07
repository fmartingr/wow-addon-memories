package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "rewrite the expected output in testdata/expected")

const wowDir = "../../testdata/wow"

func hashTree(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(b)
		rel, _ := filepath.Rel(root, path)
		out[filepath.ToSlash(rel)] = hex.EncodeToString(sum[:])
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func readTree(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := os.ReadFile(path)
		rel, _ := filepath.Rel(root, path)
		out[filepath.ToSlash(rel)] = string(b)
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func execute(args ...string) (code int, stdout, stderr string) {
	var out, errOut bytes.Buffer
	code = run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestExportFixture(t *testing.T) {
	before := hashTree(t, wowDir)
	tmp := t.TempDir()
	dist, backup := filepath.Join(tmp, "dist"), filepath.Join(tmp, "backups")

	code, stdout, stderr := execute("--wow-dir", wowDir, "--dist", dist, "--backup", backup)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, stderr)
	}
	for _, want := range []string{
		"Memories_Social.lua: line 4, column 1",
		"eu-brumamar-nandu: 15 records, 3 trail points, 1 sessions, 2 screenshots, addons Memories, Memories_Combat, Memories_Gathering",
		"skipped 1 lines",
		"joined 2 notes",
		"copied 2 screenshots, 1 not found",
	} {
		if !strings.Contains(stdout, want) {
			t.Errorf("output misses %q:\n%s", want, stdout)
		}
	}

	got := readTree(t, dist)
	expectedDir := filepath.Join("testdata", "expected")
	if *update {
		if err := os.RemoveAll(expectedDir); err != nil {
			t.Fatal(err)
		}
		if err := os.CopyFS(expectedDir, os.DirFS(dist)); err != nil {
			t.Fatal(err)
		}
	}
	want := readTree(t, expectedDir)
	if !reflect.DeepEqual(got, want) {
		for name := range want {
			if got[name] != want[name] {
				t.Errorf("%s differs:\n got: %s\nwant: %s", name, got[name], want[name])
			}
		}
		for name := range got {
			if _, ok := want[name]; !ok {
				t.Errorf("unexpected output file %s", name)
			}
		}
	}

	backups, err := filepath.Glob(filepath.Join(backup, "*", "savedvariables", "wow", "TESTACCOUNT", "*", "*", "SavedVariables", "*.lua"))
	if err != nil || len(backups) != 5 {
		t.Errorf("character backups: %v %v", backups, err)
	}
	shots, _ := filepath.Glob(filepath.Join(backup, "*", "screenshots", "*.jpg"))
	if len(shots) != 2 {
		t.Errorf("screenshot backups: %v", shots)
	}

	code, _, stderr = execute("--wow-dir", wowDir, "--dist", dist, "--backup", backup)
	if code != 0 {
		t.Fatalf("second run exit %d: %s", code, stderr)
	}
	if again := readTree(t, dist); !reflect.DeepEqual(again, got) {
		t.Error("a second run with no new data changed the output")
	}

	if after := hashTree(t, wowDir); !reflect.DeepEqual(after, before) {
		t.Errorf("the input folder changed:\nbefore %v\nafter  %v", before, after)
	}
}

func TestUsageErrors(t *testing.T) {
	tmp := t.TempDir()
	cases := []struct {
		name string
		args []string
		code int
		msg  string
	}{
		{"no arguments", nil, 2, "usage:"},
		{"help", []string{"-h"}, 0, "-wow-dir"},
		{"unknown flag", []string{"--nope"}, 2, "flag provided but not defined"},
		{"extra argument", []string{"--wow-dir", wowDir, "x"}, 2, "usage:"},
		{"unknown default", []string{"--wow-dir", wowDir, "--dist", filepath.Join(tmp, "d"), "--backup", filepath.Join(tmp, "b"), "--default", "eu-x-y"}, 2, "is not a character id"},
		{"dist in WTF", []string{"--wow-dir", wowDir, "--dist", filepath.Join(wowDir, "WTF", "out")}, 2, "never writes"},
		{"backup in Screenshots", []string{"--wow-dir", wowDir, "--dist", filepath.Join(tmp, "d"), "--backup", filepath.Join(wowDir, "Screenshots")}, 2, "never writes"},
		{"not a flavor folder", []string{"--wow-dir", tmp, "--dist", filepath.Join(tmp, "d"), "--backup", filepath.Join(tmp, "b")}, 1, "no WTF/Account folder"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			code, _, stderr := execute(tc.args...)
			if code != tc.code || !strings.Contains(stderr, tc.msg) {
				t.Fatalf("exit %d, stderr %q", code, stderr)
			}
		})
	}
	if _, err := os.Stat(filepath.Join(wowDir, "WTF", "out")); err == nil {
		t.Fatal("a refused run wrote into WTF")
	}
}
