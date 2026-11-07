package export

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/fmartingr/wow-addon-memories/internal/journal"
)

func TestSlug(t *testing.T) {
	cases := map[string]string{
		"Neral-Brumamar": "neral-brumamar",
		"Ñandú":          "nandu",
		"Los Errantes":   "los-errantes",
		"  Zul'jin!! ":   "zul-jin",
		"Ⅻ ﬁre":          "xii-fire",
		"日本":             "",
	}
	for in, want := range cases {
		if got := Slug(in); got != want {
			t.Errorf("Slug(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestRegion(t *testing.T) {
	if got := Region("SET locale \"esES\"\nSET portal \"EU\"\n"); got != "eu" {
		t.Errorf("got %q", got)
	}
	if got := Region("SET locale \"esES\"\n"); got != "xx" {
		t.Errorf("got %q", got)
	}
	if got := Region(`SET portal "__"`); got != "xx" {
		t.Errorf("got %q", got)
	}
}

func TestIDs(t *testing.T) {
	if got := BaseID("eu", "Brumamar", "Neral", "Player-1"); got != "eu-brumamar-neral" {
		t.Errorf("got %q", got)
	}
	if got := BaseID("eu", "Brumamar", "日本", "Player-1"); got != "eu-player-1" {
		t.Errorf("got %q", got)
	}
	taken := map[string]string{}
	steps := []struct{ base, guid, want string }{
		{"eu-brumamar-nandu", "Player-1", "eu-brumamar-nandu"},
		{"eu-los-errantes-nandu", "Player-2", "eu-los-errantes-nandu"},
		{"eu-brumamar-nandu", "Player-1", "eu-brumamar-nandu"},
		{"eu-brumamar-nandu", "Player-3", "eu-brumamar-nandu-forever"},
		{"eu-brumamar-nandu", "Player-4", "eu-brumamar-nandu-player-4"},
		{"eu-brumamar-nandu", "player-4", "eu-brumamar-nandu-player-4-2"},
	}
	for _, s := range steps {
		if got := AssignID(taken, s.base, "_forever_", s.guid); got != s.want {
			t.Errorf("AssignID(%s, %s) = %q, want %q", s.base, s.guid, got, s.want)
		}
		if !IDPattern.MatchString(s.want) {
			t.Errorf("%q is not a valid id", s.want)
		}
	}
}

func rec(t int64, k string, kv ...any) journal.Record {
	r := journal.Record{"t": t, "k": k}
	for i := 0; i+1 < len(kv); i += 2 {
		r[kv[i].(string)] = kv[i+1]
	}
	return r
}

func kinds(rs []journal.Record) []string {
	var out []string
	for _, r := range rs {
		out = append(out, r.String("k"))
	}
	return out
}

func TestJoinNotesExactAndTwoNotes(t *testing.T) {
	in := []journal.Record{
		rec(10, "ss", "file", "A.jpg", "result", "ok"),
		rec(10, "sn", "source", "Paparazzi", "note", "one", "file", "A.jpg"),
		rec(11, "sn", "source", "Other", "note", "two", "file", "A.jpg"),
	}
	out, joined := JoinNotes(in)
	if joined != 2 || !reflect.DeepEqual(kinds(out), []string{"ss"}) {
		t.Fatalf("got %d %v", joined, out)
	}
	want := []Note{{"Paparazzi", "one"}, {"Other", "two"}}
	if !reflect.DeepEqual(out[0]["notes"], want) {
		t.Fatalf("notes %v", out[0]["notes"])
	}
}

func TestJoinNotesNearest(t *testing.T) {
	in := []journal.Record{
		rec(10, "ss", "file", "A.jpg", "result", "ok"),
		rec(11, "sn", "source", "S", "note", "near", "file", "B.jpg"),
		rec(12, "sn", "source", "S", "note", "taken"),
		rec(30, "ss", "result", "failed"),
		rec(31, "sn", "source", "S", "note", "failed shot"),
		rec(50, "sn", "source", "S", "note", "alone"),
	}
	out, joined := JoinNotes(in)
	if joined != 1 {
		t.Fatalf("joined %d", joined)
	}
	if !reflect.DeepEqual(kinds(out), []string{"ss", "sn", "ss", "sn", "sn"}) {
		t.Fatalf("kinds %v", kinds(out))
	}
	if !reflect.DeepEqual(out[0]["notes"], []Note{{"S", "near"}}) {
		t.Fatalf("notes %v", out[0]["notes"])
	}
}

func TestJoinNotesTie(t *testing.T) {
	in := []journal.Record{
		rec(10, "ss", "result", "ok"),
		rec(11, "sn", "source", "S", "note", "tie"),
		rec(12, "ss", "result", "ok"),
	}
	out, joined := JoinNotes(in)
	if joined != 0 || len(out) != 3 || out[0]["notes"] != nil || out[2]["notes"] != nil {
		t.Fatalf("got %d %v", joined, out)
	}
}

func TestFileTime(t *testing.T) {
	got, ok := FileTime("WoWScrnShot_110626_140309.jpg", 3600)
	if !ok || got != 1793970189 {
		t.Fatalf("got %d %v", got, ok)
	}
	utc, _ := FileTime("WoWScrnShot_110626_140309.jpg", 0)
	if utc-got != 3600 {
		t.Fatalf("the offset is not applied: %d %d", utc, got)
	}
	for _, bad := range []string{"WoWScrnShot_1.jpg", "WoWScrnShot_139926_140309.jpg"} {
		if _, ok := FileTime(bad, 0); ok {
			t.Errorf("%s parsed", bad)
		}
	}
}

func TestMatchShots(t *testing.T) {
	const tz = 3600
	base, _ := FileTime("WoWScrnShot_110626_140309.jpg", tz)
	files := []string{
		"WoWScrnShot_110626_140309.jpg",
		"WoWScrnShot_110626_140308.jpg",
		"WoWScrnShot_110626_150000.jpg",
		"WoWScrnShot_110626_150002.jpg",
		"WoWScrnShot_110626_160000.jpg",
	}
	t15, _ := FileTime("WoWScrnShot_110626_150001.jpg", tz)
	t16, _ := FileTime("WoWScrnShot_110626_160000.jpg", tz)
	shots := []Shot{
		{File: "WoWScrnShot_110626_140309.jpg", T: base, TZ: tz, HasTZ: true},
		{File: "WoWScrnShot_110626_140310.jpg", T: base + 1, TZ: tz, HasTZ: true},
		{File: "WoWScrnShot_110626_150001.jpg", T: t15, TZ: tz, HasTZ: true},
		{File: "WoWScrnShot_110626_160001.jpg", T: t16 + 1, HasTZ: false},
		{File: "WoWScrnShot_110626_170000.jpg", T: t16 + 3600, TZ: tz, HasTZ: true},
		{File: "WoWScrnShot_110626_160000.jpg", T: 0, HasTZ: false},
	}
	claimed := map[string]bool{"WoWScrnShot_110626_160000.jpg": true}
	got := MatchShots(shots, files, claimed)
	want := []int{0, 1, -1, -1, -1, -1}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	if !claimed["WoWScrnShot_110626_140308.jpg"] || claimed["WoWScrnShot_110626_150000.jpg"] {
		t.Fatalf("claimed %v", claimed)
	}
}

func TestMatchShotsTimeZone(t *testing.T) {
	files := []string{"WoWScrnShot_110626_140309.jpg"}
	utc, _ := FileTime(files[0], 0)
	east := []Shot{{File: "x", T: utc - 7200, TZ: 7200, HasTZ: true}}
	if got := MatchShots(east, files, map[string]bool{}); got[0] != 0 {
		t.Fatalf("UTC+2: %v", got)
	}
	wrong := []Shot{{File: "x", T: utc - 7200, TZ: 0, HasTZ: true}}
	if got := MatchShots(wrong, files, map[string]bool{}); got[0] != -1 {
		t.Fatalf("a wrong zone matched: %v", got)
	}
}

func TestMergeRecords(t *testing.T) {
	old := []journal.Record{
		rec(1, "in", "session", json.Number("1")),
		rec(2, "ss", "file", "A.jpg", "screenshot", "screenshots/A.jpg", "notes", []any{"n"}),
		rec(2, "ss", "file", "A.jpg"),
		rec(5, "lv", "level", json.Number("2")),
	}
	fresh := []journal.Record{
		rec(1, "in", "session", 1),
		rec(2, "ss", "file", "A.jpg"),
		rec(3, "xp", "amount", int64(10)),
		rec(3, "xp", "amount", int64(10)),
	}
	out := MergeRecords(old, fresh)
	if !reflect.DeepEqual(kinds(out), []string{"in", "ss", "ss", "xp", "xp", "lv"}) {
		t.Fatalf("kinds %v", kinds(out))
	}
	if out[1]["screenshot"] != "screenshots/A.jpg" || out[1]["notes"] == nil {
		t.Fatalf("the screenshot of the earlier copy is lost: %v", out[1])
	}
	if out[2]["screenshot"] != nil {
		t.Fatalf("second copy: %v", out[2])
	}
	if again := MergeRecords(out, fresh); len(again) != len(out) {
		t.Fatalf("a second merge grew: %d", len(again))
	}
}

func TestMergeRecordsKeepsEarlierNoteJoin(t *testing.T) {
	first, _ := JoinNotes([]journal.Record{rec(100, "ss"), rec(101, "sn", "source", "X", "note", "hi")})
	b, err := marshalLine(MergeRecords(nil, first))
	if err != nil {
		t.Fatal(err)
	}
	var old []journal.Record
	if err := json.Unmarshal(b, &old); err != nil {
		t.Fatal(err)
	}
	// A later ss within NoteTolerance makes a tie, so this run leaves the sn record alone.
	fresh, joined := JoinNotes([]journal.Record{rec(100, "ss"), rec(101, "sn", "source", "X", "note", "hi"), rec(102, "ss")})
	if joined != 0 {
		t.Fatalf("joined %d", joined)
	}
	out := MergeRecords(old, fresh)
	if !reflect.DeepEqual(kinds(out), []string{"ss", "ss"}) || out[0]["notes"] == nil {
		t.Fatalf("the note is lost or held twice: %v", out)
	}
}

func i64(n int64) *int64 { return &n }

func TestMergeTrail(t *testing.T) {
	old := []journal.Chunk{{S: i64(1), T: 10, M: 5, N: 2}, {T: 30, M: 5, N: 1}}
	fresh := []journal.Chunk{{S: i64(1), T: 10, M: 5, N: 4}, {S: i64(1), T: 20, M: 6, N: 1}, {S: i64(1), T: 20, M: 5, N: 1}}
	out := MergeTrail(old, fresh)
	var got [][2]int64
	for _, c := range out {
		got = append(got, [2]int64{c.T, int64(c.N)})
	}
	want := [][2]int64{{10, 4}, {20, 1}, {20, 1}, {30, 1}}
	if !reflect.DeepEqual(got, want) || out[1].M != 5 {
		t.Fatalf("got %v", out)
	}
}

func TestMergeSessionsAndSessionAt(t *testing.T) {
	old := []any{
		map[string]any{"start": json.Number("100"), "last": json.Number("150"), "computer": "a", "tz": json.Number("3600")},
		map[string]any{"start": json.Number("300"), "last": json.Number("400"), "computer": "a"},
		"bad",
		map[string]any{"last": json.Number("1")},
	}
	fresh := []any{
		map[string]any{"start": int64(100), "last": int64(200), "computer": "a", "tz": int64(3600)},
		map[string]any{"start": int64(100), "computer": "b"},
	}
	s := MergeSessions(old, fresh)
	if len(s) != 3 || s[0]["computer"] != "a" || s[0]["last"] != int64(200) || s[1]["computer"] != "b" {
		t.Fatalf("got %v", s)
	}
	cases := []struct {
		t     int64
		index int
		tz    int64
		hasTZ bool
	}{
		{50, 0, 0, false},
		{150, 1, 3600, true},
		{100, 2, 0, false},
		{350, 3, 0, false},
		{500, 0, 0, false},
	}
	for _, c := range cases {
		i, tz, has := SessionAt(s, c.t)
		if i != c.index || tz != c.tz || has != c.hasTZ {
			t.Errorf("SessionAt(%d) = %d %d %v", c.t, i, tz, has)
		}
	}
	only := MergeSessions(fresh[:1])
	if i, tz, has := SessionAt(only, 250); i != 0 || tz != 3600 || !has {
		t.Errorf("after the end: %d %d %v", i, tz, has)
	}
}

func TestFiles(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src.jpg")
	if err := os.WriteFile(src, []byte("img"), 0o600); err != nil {
		t.Fatal(err)
	}
	dst := filepath.Join(dir, "out", "a.jpg")
	if did, err := copyFile(src, dst); !did || err != nil {
		t.Fatalf("copy: %v %v", did, err)
	}
	if did, err := copyFile(src, dst); did || err != nil {
		t.Fatalf("second copy: %v %v", did, err)
	}
	link := filepath.Join(dir, "link.jpg")
	if err := os.Symlink(src, link); err != nil {
		t.Fatal(err)
	}
	if _, err := copyFile(link, filepath.Join(dir, "b.jpg")); err == nil {
		t.Fatal("a link was copied")
	}
	if _, err := copyFile(filepath.Join(dir, "none"), filepath.Join(dir, "c.jpg")); err == nil {
		t.Fatal("a missing file was copied")
	}

	if rows, err := readJSONL[journal.Record](filepath.Join(dir, "none.jsonl")); rows != nil || err != nil {
		t.Fatalf("missing jsonl: %v %v", rows, err)
	}
	bad := filepath.Join(dir, "bad.jsonl")
	if err := os.WriteFile(bad, []byte("{\"t\":1}\n\n{nope\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := readJSONL[journal.Record](bad); err == nil {
		t.Fatal("a damaged jsonl was read")
	}
	if m, err := readJSON(filepath.Join(dir, "none.json")); m != nil || err != nil {
		t.Fatalf("missing json: %v %v", m, err)
	}
	if err := os.WriteFile(bad, []byte("[1]"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := readJSON(bad); err == nil {
		t.Fatal("a damaged json was read")
	}
	if _, err := readJSON(dir); err == nil {
		t.Fatal("a folder was read")
	}
	if _, err := readJSONL[journal.Record](dir); err == nil {
		t.Fatal("a folder was read as jsonl")
	}
}

func TestInside(t *testing.T) {
	dir := t.TempDir()
	wtf := filepath.Join(dir, "wow", "WTF")
	if err := os.MkdirAll(wtf, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "elsewhere")
	if err := os.Symlink(wtf, link); err != nil {
		t.Fatal(err)
	}
	cases := map[string]bool{
		wtf:                                 true,
		filepath.Join(wtf, "a", "b"):        true,
		filepath.Join(link, "new"):          true,
		filepath.Join(dir, "wow", "WTF2"):   false,
		filepath.Join(dir, "wow"):           false,
		filepath.Join(dir, "dist-out", "x"): false,
	}
	for path, want := range cases {
		if got := inside(path, wtf); got != want {
			t.Errorf("inside(%s) = %v", path, got)
		}
	}
}
