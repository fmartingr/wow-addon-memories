package merge

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"math/rand/v2"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

const (
	mergeDir    = "../../../testdata/merge"
	expectedDir = "../../../testdata/expected"
)

var testFiles = []string{"character.json", "journey.jsonl", "trail.jsonl"}

func readFile(t testing.TB, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func decode(t testing.TB, b []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

func lines(t testing.TB, b []byte) []any {
	t.Helper()
	out := []any{}
	for _, line := range bytes.Split(b, []byte("\n")) {
		if len(bytes.TrimSpace(line)) > 0 {
			out = append(out, decode(t, line))
		}
	}
	return out
}

// read checks a folder with the validator, the way the server checks an upload, and returns the upload.
func read(t testing.TB, dir string) *validate.Upload {
	t.Helper()
	doc, err := json.Marshal(map[string]any{
		"character": decode(t, readFile(t, filepath.Join(dir, "character.json"))),
		"journey":   lines(t, readFile(t, filepath.Join(dir, "journey.jsonl"))),
		"trail":     lines(t, readFile(t, filepath.Join(dir, "trail.jsonl"))),
	})
	if err != nil {
		t.Fatal(err)
	}
	return readDoc(t, doc)
}

func readDoc(t testing.TB, doc []byte) *validate.Upload {
	t.Helper()
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(doc); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	lim := validate.Limits{MaxDecodedBytes: 64 << 20, MaxText: 512, MaxRecords: 500_000, MaxChunks: 50_000, MaxPoints: 20_000}
	up, problems := validate.Read(&buf, lim, time.Unix(1794100000, 0))
	if len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	return up
}

func files(t testing.TB, u *validate.Upload) map[string][]byte {
	t.Helper()
	out := map[string][]byte{}
	for name, write := range map[string]func() ([]byte, error){
		"character.json": u.CharacterJSON,
		"journey.jsonl":  u.JourneyJSONL,
		"trail.jsonl":    u.TrailJSONL,
	} {
		b, err := write()
		if err != nil {
			t.Fatal(err)
		}
		out[name] = b
	}
	return out
}

func assertFiles(t *testing.T, got *validate.Upload, dir string) {
	t.Helper()
	have := files(t, got)
	for _, name := range testFiles {
		if want := readFile(t, filepath.Join(dir, name)); !bytes.Equal(have[name], want) {
			t.Errorf("%s differs from %s:\n got %s\nwant %s", name, dir, have[name], want)
		}
	}
}

func assertSame(t *testing.T, got, want *validate.Upload) {
	t.Helper()
	a, b := files(t, got), files(t, want)
	for _, name := range testFiles {
		if !bytes.Equal(a[name], b[name]) {
			t.Errorf("%s differs:\n got %s\nwant %s", name, a[name], b[name])
		}
	}
}

func fixture(t testing.TB) (old, fresh *validate.Upload) {
	t.Helper()
	return read(t, filepath.Join(mergeDir, "old")), read(t, filepath.Join(mergeDir, "fresh"))
}

// The fixture is the contract with the Dart core: merge_contract_test.dart reads the same folders.
func TestFixtureGolden(t *testing.T) {
	old, fresh := fixture(t)
	assertFiles(t, Character(old, fresh, true), filepath.Join(mergeDir, "expected"))
}

func TestFixtureFilesAreInStoredForm(t *testing.T) {
	for _, dir := range []string{"old", "fresh", "expected"} {
		assertFiles(t, read(t, filepath.Join(mergeDir, dir)), filepath.Join(mergeDir, dir))
	}
}

func TestIdempotent(t *testing.T) {
	old, fresh := fixture(t)
	once := Character(old, fresh, true)
	assertSame(t, Character(once, fresh, true), once)
	assertSame(t, Character(once, once, true), once)
	// A key with no approval keeps the screenshots that the stored data holds.
	assertSame(t, Character(once, fresh, false), once)
}

func TestInputsAreNotChanged(t *testing.T) {
	old, fresh := fixture(t)
	beforeOld, beforeFresh := files(t, old), files(t, fresh)
	Character(old, fresh, false)
	Character(old, fresh, true)
	for name, b := range files(t, old) {
		if !bytes.Equal(b, beforeOld[name]) {
			t.Errorf("old %s changed", name)
		}
	}
	for name, b := range files(t, fresh) {
		if !bytes.Equal(b, beforeFresh[name]) {
			t.Errorf("fresh %s changed", name)
		}
	}
}

func find(recs []validate.Record, k string, t int64) []validate.Record {
	var out []validate.Record
	for _, r := range recs {
		if textOf(r, "k") == k && timeOf(r) == t {
			out = append(out, r)
		}
	}
	return out
}

func kindsAt(recs []validate.Record, t int64) []string {
	var out []string
	for _, r := range recordsAt(recs, t) {
		out = append(out, textOf(r, "k"))
	}
	return out
}

func notesText(r validate.Record) string {
	var parts []string
	for _, n := range notesOf(r["notes"]) {
		parts = append(parts, n.source+":"+n.note)
	}
	return strings.Join(parts, ",")
}

func TestFixtureCases(t *testing.T) {
	old, fresh := fixture(t)
	got := Character(old, fresh, true)
	const t0 = 1793530000
	tests := []struct {
		name  string
		check func(t *testing.T)
	}{
		{"a record in both lists appears once", func(t *testing.T) {
			if n := len(find(got.Records, "in", t0)); n != 1 {
				t.Errorf("in records = %d, want 1", n)
			}
		}},
		{"a record twice in old and once in fresh is kept twice", func(t *testing.T) {
			if n := len(find(got.Records, "zo", t0+100)); n != 2 {
				t.Errorf("zo records = %d, want 2", n)
			}
		}},
		{"a fresh record takes the screenshot and notes of its old copy", func(t *testing.T) {
			r := find(got.Records, "ss", t0+150)
			if len(r) != 1 || textOf(r[0], "screenshot") != "screenshots/WoWScrnShot_110126_114820.jpg" || notesText(r[0]) != "Paparazzi:Level up" {
				t.Errorf("ss = %v", r)
			}
		}},
		{"an sn note already on an old ss is dropped, other sn records stay", func(t *testing.T) {
			if n := len(find(got.Records, "sn", t0+201)); n != 0 {
				t.Errorf("sn at +201 kept, want dropped")
			}
			if n := len(find(got.Records, "sn", t0+204)); n != 1 {
				t.Errorf("sn at +204 (more than 2 s away) = %d, want 1", n)
			}
			if n := len(find(got.Records, "sn", t0+260)); n != 1 {
				t.Errorf("sn with no stored copy = %d, want 1", n)
			}
		}},
		{"a fresh screenshot that old lacks stays", func(t *testing.T) {
			r := find(got.Records, "ss", t0+250)
			if len(r) != 1 || textOf(r[0], "screenshot") == "" {
				t.Errorf("ss = %v", r)
			}
		}},
		{"a record only in old stays", func(t *testing.T) {
			if n := len(find(got.Records, "lv", t0+280)); n != 1 {
				t.Errorf("lv records = %d, want 1", n)
			}
		}},
		{"records with the same time follow the order of fresh", func(t *testing.T) {
			if k := kindsAt(got.Records, 1793540010); !reflect.DeepEqual(k, []string{"ki", "ga"}) {
				t.Errorf("kinds = %v, want [ki ga]", k)
			}
		}},
		{"a trail chunk that grew keeps the larger n", func(t *testing.T) {
			var n []int
			for _, c := range got.Chunks {
				if c.T == t0+10 {
					n = append(n, c.N)
				}
			}
			if !reflect.DeepEqual(n, []int{4}) {
				t.Errorf("n = %v, want [4]", n)
			}
		}},
		{"a tie of a trail chunk goes to fresh", func(t *testing.T) {
			var xs []int64
			for _, c := range got.Chunks {
				if c.T == 1793540020 && len(c.Pts) > 0 {
					xs = append(xs, c.Pts[0].X)
				}
			}
			if !reflect.DeepEqual(xs, []int64{4610}) {
				t.Errorf("x = %v, want the fresh [4610]", xs)
			}
		}},
		{"chunks are sorted by time, a null session first", func(t *testing.T) {
			var ts []int64
			for _, c := range got.Chunks {
				ts = append(ts, c.T)
			}
			if !reflect.DeepEqual(ts, []int64{1793529000, 1793530010, 1793540020, 1793550010}) {
				t.Errorf("chunk times = %v", ts)
			}
		}},
		{"a session with a later last wins, and a shorter one does not", func(t *testing.T) {
			last := map[int64]int64{}
			for _, s := range mergeSessions(sessionsOf(got.Character)) {
				start, _ := intOf(s["start"])
				last[start], _ = intOf(s["last"])
			}
			want := map[int64]int64{t0: t0 + 300, 1793540000: 1793540500, 1793550000: 1793550200}
			if !reflect.DeepEqual(last, want) {
				t.Errorf("last = %v, want %v", last, want)
			}
		}},
		{"a record in no session has a null session", func(t *testing.T) {
			for _, at := range []int64{1793529900, 1793535000} {
				recs := recordsAt(got.Records, at)
				if len(recs) == 0 {
					t.Errorf("t=%d has no records", at)
				}
				for _, r := range recs {
					if v, ok := r["session"]; !ok || v != nil {
						t.Errorf("t=%d session = %v, want null", at, v)
					}
				}
			}
		}},
		{"a record in a session has its index", func(t *testing.T) {
			if s := find(got.Records, "zo", 1793550100)[0]["session"]; s != json.Number("3") {
				t.Errorf("session = %v, want 3", s)
			}
		}},
		{"the fresh character is kept, an addon only in old is added, and fresh wins the rest", func(t *testing.T) {
			if got.Character["level"] != json.Number("11") {
				t.Errorf("level = %v, want 11", got.Character["level"])
			}
			addons := got.Character["addons"].(map[string]any)
			if len(addons) != 3 {
				t.Errorf("addons = %v, want 3 entries", addons)
			}
			if w := addons["Memories"].(jsonw.Ordered)[3].Value; w != "0.2.0" {
				t.Errorf("Memories writtenBy = %v, want 0.2.0", w)
			}
			if w := addons["Memories_Combat"].(jsonw.Ordered)[3].Value; w != "0.1.0" {
				t.Errorf("Memories_Combat writtenBy = %v, want 0.1.0", w)
			}
		}},
		{"the path parts come from fresh", func(t *testing.T) {
			if got.Flavor != "wow" || got.Region != "eu" || got.Realm != "brumamar" || got.Name != "nandu" {
				t.Errorf("path = %s/%s/%s/%s", got.Flavor, got.Region, got.Realm, got.Name)
			}
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, tt.check)
	}
}

func recordsAt(recs []validate.Record, t int64) []validate.Record {
	var out []validate.Record
	for _, r := range recs {
		if timeOf(r) == t {
			out = append(out, r)
		}
	}
	return out
}

func TestEdgeCases(t *testing.T) {
	old, fresh := fixture(t)
	empty := &validate.Upload{Character: map[string]any{}}
	t.Run("both empty", func(t *testing.T) {
		got := Character(empty, empty, true)
		if len(got.Records) != 0 || len(got.Chunks) != 0 {
			t.Errorf("records = %d, chunks = %d, want none", len(got.Records), len(got.Chunks))
		}
		if _, err := got.CharacterJSON(); err != nil {
			t.Error(err)
		}
	})
	t.Run("a first upload has no old data", func(t *testing.T) {
		for _, o := range []*validate.Upload{nil, empty} {
			got := Character(o, fresh, true)
			if len(got.Records) != len(fresh.Records) || len(got.Chunks) != len(fresh.Chunks) {
				t.Errorf("records = %d, chunks = %d", len(got.Records), len(got.Chunks))
			}
			if n := len(got.Character["addons"].(map[string]any)); n != 2 {
				t.Errorf("addons = %d, want the 2 of fresh", n)
			}
		}
	})
	t.Run("an upload with an empty journey keeps the stored records", func(t *testing.T) {
		bare := &validate.Upload{Character: fresh.Character}
		got := Character(old, bare, true)
		if len(got.Records) != len(old.Records) || len(got.Chunks) != len(old.Chunks) {
			t.Errorf("records = %d, chunks = %d, want %d and %d", len(got.Records), len(got.Chunks), len(old.Records), len(old.Chunks))
		}
	})
	t.Run("keepShots false removes the fresh screenshots and keeps the stored ones", func(t *testing.T) {
		got := Character(old, fresh, false)
		if s := textOf(find(got.Records, "ss", 1793530150)[0], "screenshot"); s == "" {
			t.Error("the screenshot of old is gone")
		}
		if s, ok := find(got.Records, "ss", 1793530250)[0]["screenshot"]; ok {
			t.Errorf("a screenshot of fresh stays: %v", s)
		}
		if n := notesText(find(got.Records, "ss", 1793530200)[0]); n != "Paparazzi:Boss kill" {
			t.Errorf("notes = %q", n)
		}
	})
	t.Run("keepShots false on a first upload leaves no screenshot", func(t *testing.T) {
		for _, r := range Character(nil, fresh, false).Records {
			if _, ok := r["screenshot"]; ok {
				t.Errorf("screenshot on %v", r)
			}
		}
	})
}

func TestNotesOfForms(t *testing.T) {
	list := []any{
		jsonw.Ordered{{Key: "note", Value: "n1"}, {Key: "source", Value: "s1"}},
		map[string]any{"source": "s2", "note": "n2"},
		map[string]any{"source": 5, "note": "n3"},
		"junk",
	}
	want := []note{{"s1", "n1"}, {"s2", "n2"}, {"", "n3"}}
	if got := notesOf(list); !reflect.DeepEqual(got, want) {
		t.Errorf("notes = %v, want %v", got, want)
	}
	if got := notesOf("text"); got != nil {
		t.Errorf("notes of text = %v, want none", got)
	}
}

func TestMergeSessions(t *testing.T) {
	s := func(computer string, start, last int64) map[string]any {
		m := map[string]any{"start": json.Number(itoa(start)), "last": json.Number(itoa(last)), "tag": itoa(last)}
		if computer != "" {
			m["computer"] = computer
		}
		return m
	}
	got := mergeSessions(
		[]any{s("b", 10, 20), s("a", 10, 20), "junk", map[string]any{"computer": "a"}, s("", 5, 6)},
		[]any{s("a", 10, 20), s("b", 10, 15)},
	)
	var tags []string
	for _, m := range got {
		c, _ := m["computer"].(string)
		start, _ := intOf(m["start"])
		tags = append(tags, c+"@"+itoa(start))
	}
	if want := []string{"@5", "a@10", "b@10"}; !reflect.DeepEqual(tags, want) {
		t.Errorf("sessions = %v, want %v", tags, want)
	}
	if last := lastOf(got[2]); last != 20 {
		t.Errorf("b@10 last = %d, want the longer 20", last)
	}
	if last := lastOf(map[string]any{"start": json.Number("7")}); last != 7 {
		t.Errorf("last without last = %d, want the start", last)
	}
}

func itoa(i int64) string { return strconv.FormatInt(i, 10) }

func TestSessionAt(t *testing.T) {
	n := func(i int64) json.Number { return json.Number(itoa(i)) }
	sessions := []map[string]any{
		{"start": n(10), "last": n(50)},
		{"start": n(20), "last": n(30)},
		{"start": n(100), "last": n(110)},
	}
	tests := []struct {
		t     int64
		index int
	}{
		{5, 0},
		{10, 1},
		{25, 2},
		{35, 1},
		{50, 1},
		{15, 1},
		{60, 0},
		{105, 3},
		{200, 0},
	}
	idx := newSessionIndex(sessions)
	for _, tt := range tests {
		if index := idx.at(tt.t); index != tt.index {
			t.Errorf("at(%d) = %d, want %d", tt.t, index, tt.index)
		}
	}
	if index := newSessionIndex(nil).at(5); index != 0 {
		t.Errorf("sessionAt with no sessions = %d, want 0", index)
	}
}

// scanSessionAt is the index loop of sessionAt in merge.dart, as written there.
func scanSessionAt(sessions []map[string]any, t int64) int {
	after := sort.Search(len(sessions), func(i int) bool {
		k, _ := keyOfSession(sessions[i])
		return k.start > t
	})
	for i := after - 1; i >= 0; i-- {
		if t <= lastOf(sessions[i]) {
			return i + 1
		}
	}
	return 0
}

func TestSessionIndexMatchesTheDartScan(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	for round := range 200 {
		var list []any
		for range rng.IntN(40) {
			start := rng.Int64N(1000)
			s := map[string]any{"computer": itoa(rng.Int64N(3)), "start": json.Number(itoa(start))}
			if rng.IntN(4) > 0 {
				s["last"] = json.Number(itoa(start + rng.Int64N(300)))
			}
			list = append(list, s)
		}
		sessions := mergeSessions(list)
		index := newSessionIndex(sessions)
		for at := int64(-5); at < 1400; at++ {
			if got, want := index.at(at), scanSessionAt(sessions, at); got != want {
				t.Fatalf("round %d, t=%d: at = %d; the scan gives %d", round, at, got, want)
			}
		}
	}
}

// A time between sessions must not cost a walk through every earlier session: with 50 000 sessions and as many
// times in their gaps, that walk makes over a billion steps.
func TestSessionIndexTimesInGaps(t *testing.T) {
	const n = 50_000
	list := make([]any, n)
	for i := range list {
		start := int64(i) * 10
		list[i] = map[string]any{"start": json.Number(itoa(start)), "last": json.Number(itoa(start + 5))}
	}
	began := time.Now()
	index := newSessionIndex(mergeSessions(list))
	for i := range int64(n) {
		if got := index.at(i*10 + 7); got != 0 {
			t.Fatalf("t=%d is in session %d, want none", i*10+7, got)
		}
	}
	if took := time.Since(began); took > 5*time.Second {
		t.Errorf("%d times in gaps took %v", n, took)
	}
}

// scanTakeCarried is _takeCarried of merge.dart, as written there.
func scanTakeCarried(carried map[note][]int64, n note, t int64) bool {
	times := carried[n]
	for i, at := range times {
		if max(at-t, t-at) <= noteTolerance {
			carried[n] = slices.Delete(times, i, i+1)
			return true
		}
	}
	return false
}

func TestCarriedNotesMatchTheDartScan(t *testing.T) {
	rng := rand.New(rand.NewPCG(3, 4))
	notes := []note{{"a", "x"}, {"a", "y"}, {"b", "x"}}
	for round := range 500 {
		var got carriedNotes
		want := map[note][]int64{}
		for step := range 60 {
			n, at := notes[rng.IntN(len(notes))], rng.Int64N(20)
			if rng.IntN(2) == 0 {
				got.add(n, at)
				want[n] = append(want[n], at)
				continue
			}
			if g, w := got.take(n, at), scanTakeCarried(want, n, at); g != w {
				t.Fatalf("round %d, step %d: take(%v, %d) = %v; the scan gives %v", round, step, n, at, g, w)
			}
		}
	}
}

// An sn far from every carried copy of its note must not cost a walk through all of them: with 200 000 of each, that
// walk makes forty billion steps.
func TestCarriedNotesFarFromEveryCopy(t *testing.T) {
	const n = 200_000
	var c carriedNotes
	same := note{"s", "n"}
	for i := range int64(n) {
		c.add(same, i*10)
	}
	began := time.Now()
	for i := range int64(n) {
		if c.take(same, i*10+5) {
			t.Fatalf("t=%d took a note 5 s away", i*10+5)
		}
	}
	if took := time.Since(began); took > 5*time.Second {
		t.Errorf("%d sn records far from their notes took %v", n, took)
	}
	if !c.take(same, 12) || c.take(same, 12) {
		t.Error("an sn 2 s after one carried note takes it once")
	}
}

func TestIntOf(t *testing.T) {
	if i, ok := intOf(json.Number("7")); !ok || i != 7 {
		t.Errorf("intOf(7) = %d, %v", i, ok)
	}
	for _, v := range []any{json.Number("7.5"), "7", 7, nil} {
		if _, ok := intOf(v); ok {
			t.Errorf("intOf(%v) is a number", v)
		}
	}
}

func TestRecordKeyIgnoresDerivedKeys(t *testing.T) {
	a := validate.Record{"t": json.Number("1"), "k": "in", "session": json.Number("1"), "screenshot": "x", "notes": []any{}}
	b := validate.Record{"t": json.Number("1"), "k": "in"}
	if recordKey(a) != recordKey(b) {
		t.Errorf("keys differ: %s and %s", recordKey(a), recordKey(b))
	}
	c := validate.Record{"t": json.Number("1"), "k": "in", "bad": struct{}{}}
	if recordKey(c) == recordKey(b) {
		t.Error("a record that cannot be written has the key of another record")
	}
}

func orderOf(t *testing.T, doc []byte) []string {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(doc))
	var keys []string
	depth := 0
	expectKey := true
	for {
		tok, err := dec.Token()
		if err != nil {
			t.Fatal(err)
		}
		if d, ok := tok.(json.Delim); ok {
			if d == '{' || d == '[' {
				depth++
				continue
			}
			depth--
			if depth == 0 {
				return keys
			}
			if depth == 1 {
				expectKey = true
			}
			continue
		}
		if depth != 1 {
			continue
		}
		if s, ok := tok.(string); ok && expectKey {
			keys = append(keys, s)
		}
		expectKey = !expectKey
	}
}

func TestEntryEqualsIndexEntry(t *testing.T) {
	var index struct {
		Characters []json.RawMessage `json:"characters"`
	}
	if err := json.Unmarshal(readFile(t, filepath.Join(expectedDir, "index.json")), &index); err != nil {
		t.Fatal(err)
	}
	if len(index.Characters) < 2 {
		t.Fatalf("index.json has %d characters", len(index.Characters))
	}
	pathFields := []string{"id", "path", "journey", "trail", "character"}
	for _, raw := range index.Characters {
		want := decode(t, raw).(map[string]any)
		id := want["id"].(string)
		t.Run(id, func(t *testing.T) {
			up := read(t, filepath.Join(expectedDir, id))
			entry := Entry(id, up)
			b, err := jsonw.Marshal(entry, false)
			if err != nil {
				t.Fatal(err)
			}
			if got, wantOrder := orderOf(t, b), orderOf(t, raw); !reflect.DeepEqual(got, wantOrder) {
				t.Errorf("key order = %v, want %v", got, wantOrder)
			}
			got := decode(t, b).(map[string]any)
			for _, f := range pathFields {
				delete(got, f)
				delete(want, f)
			}
			if !reflect.DeepEqual(got, want) {
				t.Errorf("entry = %v, want %v", got, want)
			}
			if e := decode(t, b).(map[string]any); e["id"] != id || e["path"] != "." || e["journey"] != "journey.jsonl" ||
				e["trail"] != "trail.jsonl" || e["character"] != "character.json" {
				t.Errorf("path fields = %v", e)
			}
		})
	}
}

func TestEntryOfEmptyUpload(t *testing.T) {
	e := Entry("a/b/c/d", &validate.Upload{Character: map[string]any{"addons": map[string]any{"Zed": 1, "Memories": 1, "Alpha": 1}}})
	b, err := jsonw.Marshal(e, false)
	if err != nil {
		t.Fatal(err)
	}
	got := decode(t, b).(map[string]any)
	if got["start"] != nil || got["end"] != nil || got["steps"] != json.Number("0") {
		t.Errorf("entry = %v, want no start, no end and no steps", got)
	}
	if want := []any{"Memories", "Alpha", "Zed"}; !reflect.DeepEqual(got["addons"], want) {
		t.Errorf("addons = %v, want %v", got["addons"], want)
	}
}

func TestEntryOfMergedFixture(t *testing.T) {
	old, fresh := fixture(t)
	b, err := jsonw.Marshal(Entry("wow/eu/brumamar/nandu", Character(old, fresh, true)), false)
	if err != nil {
		t.Fatal(err)
	}
	got := decode(t, b).(map[string]any)
	want := map[string]any{
		"steps": json.Number("19"), "sessions": json.Number("3"), "trailPoints": json.Number("8"), "screenshots": json.Number("3"),
		"start": json.Number("1793529900"), "end": json.Number("1793550100"), "level": json.Number("11"),
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %v, want %v", k, got[k], v)
		}
	}
}
