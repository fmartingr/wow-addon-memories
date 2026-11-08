package store

import (
	"context"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func newBlobs(t *testing.T) (*DiskBlobs, string) {
	t.Helper()
	dir := t.TempDir()
	b, err := NewDiskBlobs(dir)
	if err != nil {
		t.Fatal(err)
	}
	return b, dir
}

func readBlob(t *testing.T, b Blobs, path string) string {
	t.Helper()
	f, err := b.Open(ctx, path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	got, err := io.ReadAll(f)
	if err != nil {
		t.Fatal(err)
	}
	return string(got)
}

func TestBlobsWriteOpenReplace(t *testing.T) {
	b, dir := newBlobs(t)
	if err := b.Write(ctx, "7/journey.jsonl", strings.NewReader("one")); err != nil {
		t.Fatal(err)
	}
	if got := readBlob(t, b, "7/journey.jsonl"); got != "one" {
		t.Errorf("read %q", got)
	}
	if err := b.Write(ctx, "7/journey.jsonl", strings.NewReader("two")); err != nil {
		t.Fatal(err)
	}
	if got := readBlob(t, b, "7/journey.jsonl"); got != "two" {
		t.Errorf("read %q after a replace", got)
	}
	if runtime.GOOS != "windows" {
		info, err := os.Stat(filepath.Join(dir, "characters", "7", "journey.jsonl"))
		if err != nil || info.Mode().Perm() != 0o600 {
			t.Errorf("file mode = %v, %v; want 0600", info.Mode().Perm(), err)
		}
	}
	entries, _ := os.ReadDir(filepath.Join(dir, "characters", "7"))
	if len(entries) != 1 {
		t.Errorf("the folder holds %d entries, want only the file (no temporary file)", len(entries))
	}
	f, err := b.Open(ctx, "7/journey.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if info, err := f.Stat(); err != nil || info.Size() != 3 {
		t.Errorf("Stat = %v, %v", info, err)
	}
}

type failingReader struct{}

func (failingReader) Read([]byte) (int, error) { return 0, errors.New("disk is full") }

func TestBlobsFailedWriteKeepsTheOldFileAndLeavesNoTemp(t *testing.T) {
	b, dir := newBlobs(t)
	b.Write(ctx, "1/character.json", strings.NewReader("old"))
	if err := b.Write(ctx, "1/character.json", failingReader{}); err == nil {
		t.Fatal("Write of a failing reader succeeded")
	}
	if got := readBlob(t, b, "1/character.json"); got != "old" {
		t.Errorf("read %q, want the old file", got)
	}
	entries, _ := os.ReadDir(filepath.Join(dir, "characters", "1"))
	if len(entries) != 1 {
		t.Errorf("%d entries, want 1", len(entries))
	}
}

func TestBlobsWriteStopsOnACanceledContext(t *testing.T) {
	b, _ := newBlobs(t)
	canceled, cancel := context.WithCancel(ctx)
	cancel()
	if err := b.Write(canceled, "1/entry.json", strings.NewReader("x")); err == nil {
		t.Error("Write with a canceled context succeeded")
	}
	if _, err := b.Open(ctx, "1/entry.json"); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("Open = %v, want not exist", err)
	}
}

func TestBlobsScreenshotsRemoveAndSize(t *testing.T) {
	b, _ := newBlobs(t)
	shot := "3/screenshots/WoWScrnShot_010203_040506.jpg"
	b.Write(ctx, "3/character.json", strings.NewReader("12345"))
	b.Write(ctx, shot, strings.NewReader("1234567"))
	b.Write(ctx, "4/character.json", strings.NewReader("zz"))
	if err := os.WriteFile(filepath.Join(b.root, "3", tmpPrefix+"left-by-a-crash"), []byte("123456789"), 0o600); err != nil {
		t.Fatal(err)
	}

	for prefix, want := range map[string]int64{"3": 12, "3/": 12, "3/screenshots": 7, "3/screenshots/": 7, "4": 2, "99": 0, "3/trail.jsonl": 0} {
		if got, err := b.Size(ctx, prefix); err != nil || got != want {
			t.Errorf("Size(%q) = %d, %v; want %d", prefix, got, err, want)
		}
	}
	if err := b.Remove(ctx, shot); err != nil {
		t.Fatal(err)
	}
	if err := b.Remove(ctx, shot); err != nil {
		t.Errorf("Remove of a missing file: %v", err)
	}
	if _, err := b.Open(ctx, shot); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("Open after Remove = %v", err)
	}
	if err := b.RemoveAll(ctx, "3/"); err != nil {
		t.Fatal(err)
	}
	if err := b.RemoveAll(ctx, "3/"); err != nil {
		t.Errorf("RemoveAll of a missing prefix: %v", err)
	}
	if got, _ := b.Size(ctx, "3"); got != 0 {
		t.Errorf("Size after RemoveAll = %d", got)
	}
	if got := readBlob(t, b, "4/character.json"); got != "zz" {
		t.Errorf("another claim changed: %q", got)
	}
}

func TestBlobsRejectBadPaths(t *testing.T) {
	b, dir := newBlobs(t)
	bad := []string{
		"", "/", "x", "a/character.json", "-1/character.json", "1/../2/character.json", "../1/character.json",
		"1/..", "1/.", "1//character.json", "1/memories.db", "1/screenshots", "1/screenshots/x.jpg",
		"1/screenshots/WoWScrnShot_010203_040506.tga", "1/screenshots/WoWScrnShot_010203_040506.jpg/",
		"1/screenshots/../character.json", "1/character.json/x", "1/character.json/", "1", "1/", "1/screenshots/",
		"1/.tmp-123", "1/screenshots/WoWScrnShot_010203_040506.jpg/x", "1\\character.json", "1/CHARACTER.JSON",
		"1/screenshots/WoWScrnShot_010203_04050.jpg", "\x00/character.json",
	}
	for _, p := range bad {
		if err := b.Write(ctx, p, strings.NewReader("x")); !errors.Is(err, ErrBadPath) {
			t.Errorf("Write(%q) = %v, want ErrBadPath", p, err)
		}
		if _, err := b.Open(ctx, p); !errors.Is(err, ErrBadPath) {
			t.Errorf("Open(%q) = %v, want ErrBadPath", p, err)
		}
		if err := b.Remove(ctx, p); !errors.Is(err, ErrBadPath) {
			t.Errorf("Remove(%q) = %v, want ErrBadPath", p, err)
		}
	}
	for _, p := range []string{"", "/", "x", "../x", "1/..", "1/memories.db", "1//", "1/screenshots/x.jpg", "1/character.json/x"} {
		if err := b.RemoveAll(ctx, p); !errors.Is(err, ErrBadPath) {
			t.Errorf("RemoveAll(%q) = %v, want ErrBadPath", p, err)
		}
		if _, err := b.Size(ctx, p); !errors.Is(err, ErrBadPath) {
			t.Errorf("Size(%q) = %v, want ErrBadPath", p, err)
		}
	}
	entries, _ := os.ReadDir(filepath.Join(dir, "characters"))
	if len(entries) != 0 {
		t.Errorf("a rejected path created %d entries", len(entries))
	}
}

func TestNewDiskBlobsFailsWhenTheFolderIsAFile(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "characters"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := NewDiskBlobs(dir); err == nil {
		t.Error("NewDiskBlobs succeeded over a file")
	}
}
