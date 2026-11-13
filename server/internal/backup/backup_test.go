package backup

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

func openStore(t *testing.T, dir string) *store.Store {
	t.Helper()
	st, err := store.Open(filepath.Join(dir, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	return st
}

// addClaims makes n claims of one key and returns the key id. The ids are 1 to n in a new database.
func addClaims(t *testing.T, st *store.Store, n int) int64 {
	t.Helper()
	ctx := context.Background()
	pub := bytes.Repeat([]byte{7}, 32)
	if _, err := st.Register(ctx, store.RegisterInput{Public: pub, Nonce: bytes.Repeat([]byte{7}, 16), AllowOpen: true}); err != nil {
		t.Fatal(err)
	}
	key, err := st.KeyByPublic(ctx, pub)
	if err != nil {
		t.Fatal(err)
	}
	for i := 1; i <= n; i++ {
		c := store.Claim{Flavor: "retail", Region: "eu", Realm: "realm", Name: string(rune('a' + i)), GUID: "g", KeyID: key.ID}
		if _, err := st.CreateClaim(ctx, c); err != nil {
			t.Fatal(err)
		}
	}
	return key.ID
}

func countInvites(t *testing.T, dbPath string) int {
	t.Helper()
	db, err := sql.Open("sqlite", (&url.URL{Scheme: "file", Path: filepath.ToSlash(dbPath), RawQuery: "mode=ro"}).String())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var n int
	if err := db.QueryRow(`SELECT count(*) FROM invites`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	var check string
	if err := db.QueryRow(`PRAGMA integrity_check`).Scan(&check); err != nil || check != "ok" {
		t.Fatalf("integrity_check = %q, %v", check, err)
	}
	return n
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestBackupOfALiveDatabaseHasTheRowsAndTheFiles(t *testing.T) {
	data := t.TempDir()
	st := openStore(t, data)
	blobs, err := store.NewDiskBlobs(data)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	addClaims(t, st, 2)

	const before = 20
	for i := 0; i < before; i++ {
		if _, _, err := st.CreateInvite(ctx, "before", time.Hour); err != nil {
			t.Fatal(err)
		}
	}
	if err := blobs.Write(ctx, "1/journey.jsonl", strings.NewReader("one\n")); err != nil {
		t.Fatal(err)
	}
	if err := blobs.Write(ctx, "1/screenshots/WoWScrnShot_010203_040506.jpg", bytes.NewReader([]byte{1, 2, 3, 4})); err != nil {
		t.Fatal(err)
	}
	if err := blobs.Write(ctx, "2/character.json", strings.NewReader("{}\n")); err != nil {
		t.Fatal(err)
	}
	// A write that is not done yet must not reach the backup.
	writeFile(t, filepath.Join(data, "characters", "1", ".tmp-123"), "half")

	// The server keeps writing while the backup runs.
	stop := make(chan struct{})
	var wg sync.WaitGroup
	var writeErr error
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
			}
			if _, _, err := st.CreateInvite(ctx, "during", time.Hour); err != nil {
				writeErr = err
				return
			}
		}
	}()

	dest := filepath.Join(t.TempDir(), "backup-1")
	var res Result
	for i := 0; i < 5; i++ {
		res, err = Run(ctx, data, filepath.Join(dest, string(rune('a'+i))))
		if err != nil {
			break
		}
	}
	close(stop)
	wg.Wait()
	if err != nil {
		t.Fatal(err)
	}
	if writeErr != nil {
		t.Fatalf("the server write failed during the backup: %v", writeErr)
	}

	last := filepath.Join(dest, "e")
	if got := countInvites(t, filepath.Join(last, "memories.db")); got < before {
		t.Errorf("the backup holds %d invites, want at least %d", got, before)
	}
	if res.Files != 3 || res.Bytes != 4+4+3 {
		t.Errorf("result = %+v, want 3 files and 11 bytes", res)
	}
	for path, want := range map[string]string{
		"characters/1/journey.jsonl":                             "one\n",
		"characters/1/screenshots/WoWScrnShot_010203_040506.jpg": "\x01\x02\x03\x04",
		"characters/2/character.json":                            "{}\n",
	} {
		got, err := os.ReadFile(filepath.Join(last, filepath.FromSlash(path)))
		if err != nil || string(got) != want {
			t.Errorf("%s = %q, %v; want %q", path, got, err, want)
		}
	}
	if _, err := os.Stat(filepath.Join(last, "characters", "1", ".tmp-123")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the unfinished write was copied: %v", err)
	}
	for _, p := range []string{filepath.Join(last, "memories.db"), filepath.Join(last, "characters", "2", "character.json")} {
		if info, err := os.Stat(p); err != nil || info.Mode().Perm() != 0o600 {
			t.Errorf("%s mode = %v, %v; want 0600", p, info, err)
		}
	}
	// The source folder stays as it was.
	if _, err := os.Stat(filepath.Join(data, "characters", "1", ".tmp-123")); err != nil {
		t.Errorf("the source changed: %v", err)
	}
}

func TestBackupLeavesOutTheFolderOfAClaimThatTheSnapshotLacks(t *testing.T) {
	data := t.TempDir()
	st := openStore(t, data)
	addClaims(t, st, 1)
	writeFile(t, filepath.Join(data, "characters", "1", "journey.jsonl"), "kept\n")
	writeFile(t, filepath.Join(data, "characters", "2", "journey.jsonl"), "newer than the snapshot\n")

	dest := filepath.Join(t.TempDir(), "backup")
	res, err := Run(context.Background(), data, dest)
	if err != nil {
		t.Fatal(err)
	}
	if res.Files != 1 {
		t.Errorf("files = %d, want 1", res.Files)
	}
	if _, err := os.Stat(filepath.Join(dest, "characters", "1", "journey.jsonl")); err != nil {
		t.Error(err)
	}
	if _, err := os.Stat(filepath.Join(dest, "characters", "2")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the folder of a claim outside the snapshot was copied: %v", err)
	}
}

func TestBackupLeavesOutTheFolderOfAClaimReplacedDuringTheCopy(t *testing.T) {
	data := t.TempDir()
	st := openStore(t, data)
	keyID := addClaims(t, st, 2)
	writeFile(t, filepath.Join(data, "characters", "1", "journey.jsonl"), "kept\n")
	dest := t.TempDir()
	dbPath := filepath.Join(data, "memories.db")
	ctx := context.Background()

	claims, err := snapshot(ctx, dbPath, filepath.Join(dest, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	// Between the snapshot and the copy, claim 2 is deleted and its id goes to the character of another player.
	if err := st.DeleteClaim(ctx, 2); err != nil {
		t.Fatal(err)
	}
	id, err := st.CreateClaim(ctx, store.Claim{Flavor: "retail", Region: "us", Realm: "other", Name: "z", GUID: "h", KeyID: keyID})
	if err != nil || id != 2 {
		t.Fatalf("new claim id = %d, %v; want 2", id, err)
	}
	writeFile(t, filepath.Join(data, "characters", "2", "journey.jsonl"), "another player\n")

	res, err := copyClaims(ctx, dbPath, filepath.Join(data, "characters"), filepath.Join(dest, "characters"), claims)
	if err != nil {
		t.Fatal(err)
	}
	if res.Files != 1 || res.Bytes != 5 {
		t.Errorf("result = %+v, want 1 file and 5 bytes", res)
	}
	if _, err := os.Stat(filepath.Join(dest, "characters", "1", "journey.jsonl")); err != nil {
		t.Error(err)
	}
	if _, err := os.Stat(filepath.Join(dest, "characters", "2")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the folder of the replaced claim was copied: %v", err)
	}
}

func TestBackupRefusesAFolderThatExists(t *testing.T) {
	data := t.TempDir()
	openStore(t, data)
	dest := t.TempDir()
	writeFile(t, filepath.Join(dest, "old.txt"), "keep")

	_, err := Run(context.Background(), data, dest)
	if !errors.Is(err, ErrDestExists) {
		t.Fatalf("err = %v, want ErrDestExists", err)
	}
	if got, err := os.ReadFile(filepath.Join(dest, "old.txt")); err != nil || string(got) != "keep" {
		t.Errorf("the old folder changed: %q, %v", got, err)
	}
	if entries, _ := os.ReadDir(dest); len(entries) != 1 {
		t.Errorf("the folder has %d entries, want 1", len(entries))
	}
}

func TestBackupAcceptsATrailingSlash(t *testing.T) {
	data := t.TempDir()
	openStore(t, data)
	dest := filepath.Join(t.TempDir(), "backup")
	if _, err := Run(context.Background(), data, dest+string(filepath.Separator)); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dest, "memories.db")); err != nil {
		t.Error(err)
	}
}

func TestBackupRefusesAFolderInsideTheCharacters(t *testing.T) {
	data := t.TempDir()
	openStore(t, data)
	for _, dest := range []string{filepath.Join(data, "characters"), filepath.Join(data, "characters", "7", "backup")} {
		if _, err := Run(context.Background(), data, dest); err == nil || !strings.Contains(err.Error(), "Choose a folder outside it") {
			t.Errorf("%s: err = %v", dest, err)
		}
	}
	if _, err := os.Stat(filepath.Join(data, "characters", "7")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the backup made a folder below characters: %v", err)
	}
	if _, err := Run(context.Background(), data, filepath.Join(data, "characters-backup")); err != nil {
		t.Errorf("a sibling folder with the same prefix: %v", err)
	}
}

func TestBackupWithoutADatabaseFailsAndLeavesNothing(t *testing.T) {
	data := t.TempDir()
	dest := filepath.Join(t.TempDir(), "backup")
	if _, err := Run(context.Background(), data, dest); err == nil || !strings.Contains(err.Error(), "there is no database") {
		t.Fatalf("err = %v, want the no-database message", err)
	}
	if _, err := os.Stat(dest); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the destination exists after the error: %v", err)
	}
	if _, err := os.Stat(filepath.Join(data, "memories.db")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the backup created a database: %v", err)
	}
}

func TestBackupWithNoCharactersFolderMakesAnEmptyOne(t *testing.T) {
	data := t.TempDir()
	st := openStore(t, data)
	if _, _, err := st.CreateInvite(context.Background(), "x", time.Hour); err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(t.TempDir(), "nested", "backup")
	res, err := Run(context.Background(), data, dest)
	if err != nil {
		t.Fatal(err)
	}
	if res.Files != 0 {
		t.Errorf("files = %d, want 0", res.Files)
	}
	if entries, err := os.ReadDir(filepath.Join(dest, "characters")); err != nil || len(entries) != 0 {
		t.Errorf("characters folder: %v, %v", entries, err)
	}
	if got := countInvites(t, filepath.Join(dest, "memories.db")); got != 1 {
		t.Errorf("invites = %d, want 1", got)
	}
}

func TestBackupStopsWhenTheContextEnds(t *testing.T) {
	data := t.TempDir()
	openStore(t, data)
	dest := filepath.Join(t.TempDir(), "backup")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Run(ctx, data, dest); err == nil {
		t.Fatal("want an error")
	}
	if _, err := os.Stat(dest); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the destination exists after the error: %v", err)
	}
}

func TestBackupSkipsSymlinks(t *testing.T) {
	data := t.TempDir()
	addClaims(t, openStore(t, data), 1)
	outside := filepath.Join(t.TempDir(), "secret.txt")
	writeFile(t, outside, "secret")
	writeFile(t, filepath.Join(data, "characters", "1", "journey.jsonl"), "x")
	if err := os.Symlink(outside, filepath.Join(data, "characters", "1", "link")); err != nil {
		t.Skip("symlinks are not available:", err)
	}
	dest := filepath.Join(t.TempDir(), "backup")
	if _, err := Run(context.Background(), data, dest); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(filepath.Join(dest, "characters", "1", "link")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the symlink was copied: %v", err)
	}
}

func TestBackupFailsWhenTheDestinationParentIsAFile(t *testing.T) {
	data := t.TempDir()
	openStore(t, data)
	parent := filepath.Join(t.TempDir(), "file")
	writeFile(t, parent, "x")
	if _, err := Run(context.Background(), data, filepath.Join(parent, "backup")); err == nil {
		t.Fatal("want an error")
	}
}

func TestBackupFailsAndCleansUpWhenCharactersIsAFile(t *testing.T) {
	data := t.TempDir()
	openStore(t, data)
	writeFile(t, filepath.Join(data, "characters"), "not a folder")
	dest := filepath.Join(t.TempDir(), "backup")
	if _, err := Run(context.Background(), data, dest); err == nil {
		t.Fatal("want an error")
	}
	if _, err := os.Stat(dest); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the destination exists after the error: %v", err)
	}
}

func TestBackupFailsOnAFileThatIsNotADatabase(t *testing.T) {
	data := t.TempDir()
	writeFile(t, filepath.Join(data, "memories.db"), "this is not a database, but it is long enough to be read as one")
	dest := filepath.Join(t.TempDir(), "backup")
	if _, err := Run(context.Background(), data, dest); err == nil || !strings.Contains(err.Error(), "could not copy the database") {
		t.Fatalf("err = %v", err)
	}
	if _, err := os.Stat(dest); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the destination exists after the error: %v", err)
	}
}
