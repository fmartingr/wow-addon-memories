package export

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/internal/journal"
)

const (
	mainID  = "eu-brumamar-nandu"
	otherID = "eu-los-errantes-nandu"
)

func fixture(t *testing.T) (wow, dist string) {
	t.Helper()
	root := t.TempDir()
	wow = filepath.Join(root, "_forever_")
	if err := os.CopyFS(wow, os.DirFS("../../testdata/wow")); err != nil {
		t.Fatal(err)
	}
	return wow, filepath.Join(root, "dist")
}

func runOn(t *testing.T, wow, dist string, def string) (string, error) {
	t.Helper()
	var out bytes.Buffer
	err := Run(Options{
		WowDir: wow, Dist: dist, Backup: filepath.Join(filepath.Dir(dist), "backups"), Default: def,
		Now: time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC), Out: &out,
	})
	return out.String(), err
}

func journey(t *testing.T, dist, id string) []journal.Record {
	t.Helper()
	rows, err := readJSONL[journal.Record](filepath.Join(dist, id, "journey.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	return rows
}

func indexDefault(t *testing.T, dist string) string {
	t.Helper()
	m, err := readJSON(filepath.Join(dist, "index.json"))
	if err != nil {
		t.Fatal(err)
	}
	s, _ := m["default_character"].(string)
	return s
}

func TestRunKeepsEarlierRuns(t *testing.T) {
	wow, dist := fixture(t)
	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	if got := indexDefault(t, dist); got != mainID {
		t.Fatalf("default %q", got)
	}
	f, err := os.OpenFile(filepath.Join(dist, mainID, "journey.jsonl"), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(`{"addon":"Memories","k":"lv","level":2,"t":1793529000}` + "\n"); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(wow, "Screenshots", "WoWScrnShot_110126_115001.jpg")); err != nil {
		t.Fatal(err)
	}

	if _, err := runOn(t, wow, dist, otherID); err != nil {
		t.Fatal(err)
	}
	rows := journey(t, dist, mainID)
	if len(rows) != 16 || rows[0].String("k") != "lv" || rows[0]["session"] != nil {
		t.Fatalf("the earlier record is lost or misplaced: %d %v", len(rows), rows[0])
	}
	shots := 0
	for _, r := range rows {
		if r.String("screenshot") != "" {
			shots++
		}
	}
	if shots != 2 {
		t.Fatalf("a screenshot gone from the Screenshots folder lost its link: %d", shots)
	}

	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	if got := indexDefault(t, dist); got != otherID {
		t.Fatalf("the earlier default is not kept: %q", got)
	}
}

func TestRunDamagedEarlierOutput(t *testing.T) {
	wow, dist := fixture(t)
	if err := os.MkdirAll(filepath.Join(dist, mainID), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dist, mainID, "journey.jsonl"), []byte("{broken\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	out, err := runOn(t, wow, dist, mainID)
	if err == nil || !strings.Contains(err.Error(), "1 characters and 0 accounts failed") || !strings.Contains(out, "left as it was") {
		t.Fatalf("err %v, out %s", err, out)
	}
	if got := indexDefault(t, dist); got != otherID || !strings.Contains(out, "has no entry in index.json") {
		t.Fatalf("the default names a character without an entry: %q", got)
	}
	if b, _ := os.ReadFile(filepath.Join(dist, mainID, "journey.jsonl")); string(b) != "{broken\n" {
		t.Fatal("the damaged earlier output was replaced")
	}
	if len(journey(t, dist, otherID)) != 1 {
		t.Fatal("the other character was not written")
	}
	for _, name := range []string{"trail.jsonl", "character.json"} {
		if err := os.WriteFile(filepath.Join(dist, mainID, "journey.jsonl"), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dist, mainID, name), []byte("{broken\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		if _, err := runOn(t, wow, dist, ""); err == nil {
			t.Fatalf("a damaged %s was read", name)
		}
		if err := os.Remove(filepath.Join(dist, mainID, name)); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRunEdgeFolders(t *testing.T) {
	wow, dist := fixture(t)
	acc := filepath.Join(wow, "WTF", "Account", "TESTACCOUNT")
	if err := os.Remove(filepath.Join(wow, "WTF", "Config.wtf")); err != nil {
		t.Fatal(err)
	}
	noKinds := filepath.Join(wow, "WTF", "Account", "NOKINDS")
	if err := os.CopyFS(filepath.Join(noKinds, "Brumamar", "Otra"), os.DirFS(filepath.Join(acc, "Brumamar", "Ñandú"))); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(noKinds, "Zeta", "Otra"), os.DirFS(filepath.Join(acc, "Brumamar", "Ñandú"))); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(wow, "WTF", "Account", "NODATA", "Brumamar", "Nadie", "SavedVariables"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(acc, "Otro", "Ñandú"), os.DirFS(filepath.Join(acc, "Brumamar", "Ñandú"))); err != nil {
		t.Fatal(err)
	}
	noGUID := filepath.Join(acc, "Brumamar", "Singuid", "SavedVariables")
	if err := os.MkdirAll(noGUID, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(noGUID, "Memories.lua"), []byte("MemoriesCharDB = { [\"char\"] = {} }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(noGUID, "Memories_Combat.lua"), []byte("Other = {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(acc, "Brumamar", "Empty", "SavedVariables"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(acc, "Brumamar", "Ñandú", "SavedVariables", "Memories_Combat.lua")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(acc, "Brumamar", "Ñandú", "SavedVariables", "Memories_Combat.lua"), []byte("Other = {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	out, err := runOn(t, wow, dist, "")
	if err == nil || err.Error() != "0 characters and 1 accounts failed" {
		t.Fatalf("got %v", err)
	}
	for _, want := range []string{
		"Singuid-Brumamar: no character GUID", "has the GUID of", "has no MemoriesCombatCharDB table",
		"account NOKINDS has character data but no Memories.lua",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output misses %q:\n%s", want, out)
		}
	}
	rows := journey(t, dist, "xx-brumamar-nandu")
	for _, r := range rows {
		if r.String("addon") == "Memories_Combat" {
			t.Fatal("a file without its table was read")
		}
		if r.String("k") == "ss" && r["why"] == nil {
			t.Fatal("the account kinds were not used")
		}
	}
}

func TestRunDamagedAccountFile(t *testing.T) {
	wow, dist := fixture(t)
	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(filepath.Join(dist, mainID, "journey.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	accFile := filepath.Join(wow, "WTF", "Account", "TESTACCOUNT", "SavedVariables", "Memories.lua")
	if err := os.WriteFile(accFile, []byte("MemoriesDB = {\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := runOn(t, wow, dist, ""); err == nil {
		t.Fatal("a run without the account kinds passed")
	}
	if after, _ := os.ReadFile(filepath.Join(dist, mainID, "journey.jsonl")); !bytes.Equal(after, before) {
		t.Fatal("records were written without the account kinds")
	}
}

func TestRunAccountFileWithoutKinds(t *testing.T) {
	wow, dist := fixture(t)
	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(filepath.Join(dist, mainID, "journey.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	accFile := filepath.Join(wow, "WTF", "Account", "TESTACCOUNT", "SavedVariables", "Memories.lua")
	if err := os.WriteFile(accFile, []byte("MemoriesDB = {\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if out, err := runOn(t, wow, dist, ""); err == nil || !strings.Contains(out, "has no kinds") {
		t.Fatalf("a run without the account kinds passed: %v\n%s", err, out)
	}
	if after, _ := os.ReadFile(filepath.Join(dist, mainID, "journey.jsonl")); !bytes.Equal(after, before) {
		t.Fatal("records were written without the account kinds")
	}
}

func TestRunKeepsIDsAndEntries(t *testing.T) {
	wow, dist := fixture(t)
	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(filepath.Join(wow, "WTF", "Account", "TESTACCOUNT", "Los Errantes")); err != nil {
		t.Fatal(err)
	}
	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	m, err := readJSON(filepath.Join(dist, "index.json"))
	if err != nil {
		t.Fatal(err)
	}
	list, _ := m["characters"].([]any)
	if len(list) != 2 {
		t.Fatalf("a character without saved files left the index: %v", list)
	}

	other := filepath.Join(dist, otherID, "character.json")
	if err := os.WriteFile(other, []byte(`{"guid":"Player-1234-0ABCDEF0"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dist, "index.json"), []byte(`{"characters":[{"id":"`+otherID+`","guid":"Player-1234-0ABCDEF0"}]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	if len(journey(t, dist, mainID)) == 0 {
		t.Fatal("an earlier id that the name and realm cannot give was kept")
	}
	if err := os.WriteFile(filepath.Join(dist, mainID, "character.json"), []byte(`{"guid":"Player-5678-0FEDCBA0"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if out, err := runOn(t, wow, dist, ""); err == nil || !strings.Contains(out, "holds the character with GUID") {
		t.Fatalf("a folder of another GUID was merged: %v", err)
	}
}

func TestRunKeepsFolderOfRenamedCharacter(t *testing.T) {
	wow, dist := fixture(t)
	if _, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatal(err)
	}
	gone := []byte(`{"guid":"Player-9-0000000A"}`)
	if err := os.WriteFile(filepath.Join(dist, mainID, "character.json"), gone, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dist, "index.json"), []byte(`{"characters":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if out, err := runOn(t, wow, dist, ""); err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	if len(journey(t, dist, mainID+"-forever")) == 0 {
		t.Fatal("the character did not get a free id")
	}
	if b, _ := os.ReadFile(filepath.Join(dist, mainID, "character.json")); !bytes.Equal(b, gone) {
		t.Fatal("the folder of another GUID was written")
	}
}

func TestRunDamagedIndex(t *testing.T) {
	wow, dist := fixture(t)
	if err := os.MkdirAll(dist, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dist, "index.json"), []byte("{broken"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := runOn(t, wow, dist, ""); err == nil || !strings.Contains(err.Error(), "fix or remove it") {
		t.Fatalf("got %v", err)
	}
	if b, _ := os.ReadFile(filepath.Join(dist, "index.json")); string(b) != "{broken" {
		t.Fatal("the damaged index was replaced")
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(dist), "backups")); err == nil {
		t.Fatal("a refused run wrote backups")
	}
}

func TestRunSkipsScreenshotThatCannotBeCopied(t *testing.T) {
	wow, dist := fixture(t)
	if err := os.MkdirAll(filepath.Join(dist, mainID), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dist, mainID, "screenshots"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	out, err := runOn(t, wow, dist, "")
	if err != nil || !strings.Contains(out, "screenshot skipped") {
		t.Fatalf("err %v, out %s", err, out)
	}
	for _, r := range journey(t, dist, mainID) {
		if r.String("screenshot") != "" {
			t.Fatal("a screenshot that was not copied is linked")
		}
	}
}

func TestRunNoCharacters(t *testing.T) {
	root := t.TempDir()
	wow := filepath.Join(root, "wow")
	if err := os.MkdirAll(filepath.Join(wow, "WTF", "Account", "A", "SavedVariables"), 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := runOn(t, wow, filepath.Join(root, "dist"), "")
	if err == nil || !strings.Contains(err.Error(), "no character with Memories data") {
		t.Fatalf("got %v", err)
	}
}

func TestRunRefusesSourceFolders(t *testing.T) {
	wow, _ := fixture(t)
	err := Run(Options{WowDir: wow, Dist: filepath.Join(wow, "Screenshots", "x"), Backup: filepath.Join(wow, "b")})
	if !errors.Is(err, ErrUsage) {
		t.Fatalf("got %v", err)
	}
	err = Run(Options{WowDir: wow, Dist: filepath.Join(wow, "d"), Backup: filepath.Join(wow, "WTF")})
	if !errors.Is(err, ErrUsage) {
		t.Fatalf("got %v", err)
	}
	err = Run(Options{WowDir: wow, Dist: wow, Backup: filepath.Join(filepath.Dir(wow), "b")})
	if !errors.Is(err, ErrUsage) {
		t.Fatalf("an output folder that holds WTF was accepted: %v", err)
	}
}

func TestByLevel(t *testing.T) {
	got := byLevel([]any{"a", "b"}).(map[string]any)
	if got["1"] != "a" || got["2"] != "b" {
		t.Fatalf("got %v", got)
	}
	if byLevel("x") != "x" {
		t.Fatal("a map value changed")
	}
}
