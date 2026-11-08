package characters

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

var ctx = context.Background()

const expectedDir = "../../../testdata/expected"

type fixture struct {
	t     *testing.T
	st    *store.Store
	blobs *store.DiskBlobs
	svc   *Service
	data  string
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	data := t.TempDir()
	st, err := store.Open(filepath.Join(data, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	st.SetClock(func() time.Time { return time.Unix(1794000000, 0) })
	blobs, err := store.NewDiskBlobs(data)
	if err != nil {
		t.Fatal(err)
	}
	return &fixture{t: t, st: st, blobs: blobs, data: data, svc: New(st, blobs, slog.New(slog.NewJSONHandler(io.Discard, nil)))}
}

func (f *fixture) key(n byte) store.Key {
	f.t.Helper()
	pub := bytes.Repeat([]byte{n}, 32)
	if _, err := f.st.Register(ctx, store.RegisterInput{Public: pub, Nonce: bytes.Repeat([]byte{n}, 16)}); err != nil {
		f.t.Fatal(err)
	}
	k, err := f.st.KeyByPublic(ctx, pub)
	if err != nil {
		f.t.Fatal(err)
	}
	return k
}

func upload(t *testing.T, id string) *validate.Upload {
	t.Helper()
	dir := filepath.Join(expectedDir, id)
	read := func(name string) []byte {
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	lines := func(b []byte) []json.RawMessage {
		out := []json.RawMessage{}
		for _, l := range bytes.Split(bytes.TrimSpace(b), []byte("\n")) {
			if len(l) > 0 {
				out = append(out, l)
			}
		}
		return out
	}
	raw, err := json.Marshal(map[string]any{
		"character": json.RawMessage(read("character.json")),
		"journey":   lines(read("journey.jsonl")),
		"trail":     lines(read("trail.jsonl")),
	})
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	zw.Write(raw)
	zw.Close()
	lim := validate.Limits{MaxDecodedBytes: 64 << 20, MaxText: 512, MaxRecords: 500_000, MaxChunks: 50_000, MaxPoints: 20_000}
	up, problems := validate.Read(&buf, lim, time.Unix(1794000000, 0))
	if len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	return up
}

var roomy = Quotas{MaxCharacters: 50, MaxDataBytes: 1 << 30, MaxCharacterBytes: 1 << 30}

func (f *fixture) exists(path string) bool {
	_, err := f.blobs.Open(ctx, path)
	return !errors.Is(err, fs.ErrNotExist)
}

func TestSaveThenDeleteByOwnerAndAdmin(t *testing.T) {
	f := newFixture(t)
	owner, other := f.key(1), f.key(2)
	p := Path{"wow", "eu", "brumamar", "nandu"}
	if _, err := f.svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
		t.Fatal(err)
	}
	claim, err := f.st.ClaimByPath(ctx, p.Flavor, p.Region, p.Realm, p.Name)
	if err != nil {
		t.Fatal(err)
	}
	id := strconv.FormatInt(claim.ID, 10)
	if !f.exists(id + "/journey.jsonl") {
		t.Fatal("the journey was not stored")
	}

	if err := f.svc.Delete(ctx, p, other.ID); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("a foreign delete gave %v, want not found", err)
	}
	if !f.exists(id + "/journey.jsonl") {
		t.Error("a foreign delete removed the files")
	}
	if err := f.svc.Delete(ctx, p, 0); err != nil {
		t.Fatalf("admin delete: %v", err)
	}
	if f.exists(id+"/journey.jsonl") || f.exists(id+"/entry.json") {
		t.Error("the files stayed")
	}
	if _, err := f.st.ClaimByPath(ctx, p.Flavor, p.Region, p.Realm, p.Name); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("the claim stayed: %v", err)
	}
	if err := f.svc.Delete(ctx, p, 0); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("a second delete gave %v, want not found", err)
	}
}

func TestDeleteAllOfKeyLeavesOtherKeysAlone(t *testing.T) {
	f := newFixture(t)
	a, b := f.key(1), f.key(2)
	for _, id := range []string{"eu-brumamar-nandu", "eu-los-errantes-nandu"} {
		if _, err := f.svc.Save(ctx, a, upload(t, id), roomy); err != nil {
			t.Fatal(err)
		}
	}
	third := upload(t, "eu-brumamar-nandu")
	third.Name = "copy"
	third.Character["guid"] = "Player-9-0000000A"
	if _, err := f.svc.Save(ctx, b, third, roomy); err != nil {
		t.Fatal(err)
	}

	n, err := f.svc.DeleteAllOfKey(ctx, a.ID)
	if err != nil || n != 2 {
		t.Fatalf("deleted %d, %v; want 2", n, err)
	}
	if left, _ := f.st.ClaimsOfKey(ctx, a.ID); len(left) != 0 {
		t.Errorf("%d claims left for the key", len(left))
	}
	if left, _ := f.st.ClaimsOfKey(ctx, b.ID); len(left) != 1 {
		t.Errorf("the other key has %d claims, want 1", len(left))
	}
	if n, err := f.svc.DeleteAllOfKey(ctx, a.ID); err != nil || n != 0 {
		t.Errorf("a second run deleted %d, %v; want 0", n, err)
	}
}

type removeFails struct{ store.Blobs }

func (removeFails) RemoveAll(context.Context, string) error { return errors.New("cannot remove") }

func TestDeleteKeepsTheClaimWhenTheFilesStay(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	p := Path{"wow", "eu", "brumamar", "nandu"}
	if _, err := f.svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
		t.Fatal(err)
	}
	broken := New(f.st, removeFails{f.blobs}, slog.New(slog.NewJSONHandler(io.Discard, nil)))
	if err := broken.Delete(ctx, p, owner.ID); err == nil {
		t.Fatal("the delete reported success although the files stayed")
	}
	if _, err := f.st.ClaimByPath(ctx, p.Flavor, p.Region, p.Realm, p.Name); err != nil {
		t.Errorf("the claim went before its files: %v", err)
	}
	if _, err := broken.DeleteAllOfKey(ctx, owner.ID); err == nil {
		t.Error("DeleteAllOfKey hid a failure")
	}
	if err := f.svc.Delete(ctx, p, owner.ID); err != nil {
		t.Errorf("the retry failed: %v", err)
	}
}

func TestSaveReportsADamagedStoredCharacter(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	up := upload(t, "eu-brumamar-nandu")
	if _, err := f.svc.Save(ctx, owner, up, roomy); err != nil {
		t.Fatal(err)
	}
	claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	if err := f.blobs.Write(ctx, strconv.FormatInt(claim.ID, 10)+"/character.json", bytes.NewReader([]byte("{"))); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Save(ctx, owner, up, roomy); err == nil {
		t.Error("an upload merged into damaged stored data")
	}
	if _, err := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); err != nil {
		t.Errorf("a failed re-upload removed the old claim: %v", err)
	}
}

func TestSaveAdoptsAClaimWithNoFiles(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	up := upload(t, "eu-brumamar-nandu")
	guid, _ := up.Character["guid"].(string)
	if _, err := f.st.CreateClaim(ctx, store.Claim{Flavor: "wow", Region: "eu", Realm: "brumamar", Name: "nandu", GUID: guid, KeyID: owner.ID}); err != nil {
		t.Fatal(err)
	}
	res, err := f.svc.Save(ctx, owner, up, roomy)
	if err != nil || res.Added != res.Steps || res.Steps != 15 {
		t.Errorf("result %+v, %v; want 15 steps, all added", res, err)
	}
}

func TestLoadReturnsNilForAnEmptyClaim(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	id, err := f.st.CreateClaim(ctx, store.Claim{Flavor: "wow", Region: "eu", Realm: "r", Name: "n", GUID: "g", KeyID: owner.ID})
	if err != nil {
		t.Fatal(err)
	}
	if up, err := f.svc.Load(ctx, id); up != nil || err != nil {
		t.Errorf("Load = %v, %v; want nil, nil", up, err)
	}
	if _, err := f.svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
		t.Fatal(err)
	}
	claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	if up, err := f.svc.Load(ctx, claim.ID); err != nil || up == nil || len(up.Records) != 15 {
		t.Errorf("Load = %+v, %v; want 15 records", up, err)
	}
}

func TestPathLocksOrderUsersOfOnePathAndForgetIdlePaths(t *testing.T) {
	f := newFixture(t)
	var mu sync.Mutex
	inside := 0
	var wg sync.WaitGroup
	for range 20 {
		wg.Go(func() {
			unlock := f.svc.locks.lock("a/b/c/d")
			mu.Lock()
			inside++
			if inside != 1 {
				t.Errorf("%d users inside the lock", inside)
			}
			mu.Unlock()
			time.Sleep(time.Millisecond)
			mu.Lock()
			inside--
			mu.Unlock()
			unlock()
		})
	}
	other := f.svc.locks.lock("x/y/z/w")
	other()
	wg.Wait()
	if n := len(f.svc.locks.m); n != 0 {
		t.Errorf("%d locks kept for idle paths", n)
	}
}

// flakyBlobs fails the writes that failWrite names, and every removal while failRemove is set.
type flakyBlobs struct {
	store.Blobs
	failWrite  func(name string) bool
	failRemove bool
}

func (f *flakyBlobs) Write(ctx context.Context, path string, r io.Reader) error {
	if f.failWrite != nil && f.failWrite(filepath.Base(path)) {
		return errors.New("disk full")
	}
	return f.Blobs.Write(ctx, path, r)
}

func (f *flakyBlobs) Remove(ctx context.Context, path string) error {
	if f.failRemove {
		return errors.New("disk gone")
	}
	return f.Blobs.Remove(ctx, path)
}

func (f *flakyBlobs) RemoveAll(ctx context.Context, prefix string) error {
	if f.failRemove {
		return errors.New("disk gone")
	}
	return f.Blobs.RemoveAll(ctx, prefix)
}

func (f *fixture) storedFile(claim store.Claim, name string) []byte {
	f.t.Helper()
	b, err := os.ReadFile(filepath.Join(f.data, "characters", strconv.FormatInt(claim.ID, 10), name))
	if err != nil {
		f.t.Fatal(err)
	}
	return b
}

func TestFailedSaveRestoresTheOldFiles(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	flaky := &flakyBlobs{Blobs: f.blobs}
	svc := New(f.st, flaky, slog.New(slog.NewJSONHandler(io.Discard, nil)))

	small := upload(t, "eu-brumamar-nandu")
	small.Records = small.Records[:5]
	small.Chunks = nil
	if _, err := svc.Save(ctx, owner, small, roomy); err != nil {
		t.Fatal(err)
	}
	claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	before := map[string][]byte{}
	for _, n := range dataFiles {
		before[n] = f.storedFile(claim, n)
	}

	flaky.failWrite = func(name string) bool { return name == "entry.json" }
	if _, err := svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy); err == nil {
		t.Fatal("the save hid the disk failure")
	}
	for n, b := range before {
		if !bytes.Equal(f.storedFile(claim, n), b) {
			t.Errorf("%s was not restored", n)
		}
	}
	if after, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); after.Steps != 5 {
		t.Errorf("steps = %d, want the old 5", after.Steps)
	}
}

func TestCleanupFailuresAreLoggedNotHidden(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	flaky := &flakyBlobs{Blobs: f.blobs}
	var logs bytes.Buffer
	svc := New(f.st, flaky, slog.New(slog.NewJSONHandler(&logs, nil)))

	flaky.failWrite = func(string) bool { return true }
	flaky.failRemove = true
	if _, err := svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy); err == nil {
		t.Fatal("the save hid the disk failure")
	}
	if !bytes.Contains(logs.Bytes(), []byte("files of a failed first save")) {
		t.Errorf("the failed removal of the files is not logged: %s", logs.String())
	}

	flaky.failWrite, flaky.failRemove = nil, false
	small := upload(t, "eu-brumamar-nandu")
	small.Records = small.Records[:5]
	if _, err := svc.Save(ctx, owner, small, roomy); err != nil {
		t.Fatal(err)
	}
	logs.Reset()
	journeyWrites := 0
	flaky.failWrite = func(name string) bool {
		if name == "journey.jsonl" {
			journeyWrites++
			return journeyWrites > 1
		}
		return name == "entry.json"
	}
	if _, err := svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy); err == nil {
		t.Fatal("the save hid the disk failure")
	}
	if !bytes.Contains(logs.Bytes(), []byte("restore")) {
		t.Errorf("the failed restore is not logged: %s", logs.String())
	}
}

// gateBlobs holds the first write of each save until a second save also reaches a write, or until wait passes.
type gateBlobs struct {
	store.Blobs
	wait    time.Duration
	arrived chan struct{}
}

func (g *gateBlobs) Write(ctx context.Context, path string, r io.Reader) error {
	if filepath.Base(path) == dataFiles[0] {
		select {
		case g.arrived <- struct{}{}:
		case <-g.arrived:
		case <-time.After(g.wait):
		}
	}
	return g.Blobs.Write(ctx, path, r)
}

func TestTwoPathsOfOneKeyCannotBothPassTheDataQuota(t *testing.T) {
	ids := []string{"eu-brumamar-nandu", "eu-los-errantes-nandu"}
	var sizes int64
	for _, id := range ids {
		f := newFixture(t)
		k := f.key(1)
		if _, err := f.svc.Save(ctx, k, upload(t, id), roomy); err != nil {
			t.Fatal(err)
		}
		n, err := f.st.DataBytesOfKey(ctx, k.ID, 0)
		if err != nil {
			t.Fatal(err)
		}
		sizes += n
	}

	f := newFixture(t)
	owner := f.key(1)
	svc := New(f.st, &gateBlobs{Blobs: f.blobs, wait: 300 * time.Millisecond, arrived: make(chan struct{})},
		slog.New(slog.NewJSONHandler(io.Discard, nil)))
	q := Quotas{MaxCharacters: 50, MaxDataBytes: sizes - 1, MaxCharacterBytes: 1 << 30}
	errs := make([]error, len(ids))
	var wg sync.WaitGroup
	for i, id := range ids {
		up := upload(t, id)
		wg.Go(func() { _, errs[i] = svc.Save(ctx, owner, up, q) })
	}
	wg.Wait()
	refused := 0
	for _, err := range errs {
		if errors.Is(err, ErrDataQuota) {
			refused++
		} else if err != nil {
			t.Fatal(err)
		}
	}
	if refused != 1 {
		t.Errorf("%d of 2 saves were refused, want 1", refused)
	}
	if n, _ := f.st.DataBytesOfKey(ctx, owner.ID, 0); n > q.MaxDataBytes {
		t.Errorf("the key holds %d bytes, over its quota of %d", n, q.MaxDataBytes)
	}
}

func TestSaveRefusesACharacterOverItsSizeLimit(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	up := upload(t, "eu-brumamar-nandu")
	q := roomy
	q.MaxCharacterBytes = 100
	if _, err := f.svc.Save(ctx, owner, up, q); !errors.Is(err, ErrCharacterTooLarge) {
		t.Fatalf("a first save over the limit gave %v", err)
	}
	if _, err := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("the refused first save left a claim: %v", err)
	}

	if _, err := f.svc.Save(ctx, owner, up, roomy); err != nil {
		t.Fatal(err)
	}
	claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	q.MaxCharacterBytes = claim.DataBytes - 1
	small := upload(t, "eu-brumamar-nandu")
	small.Records, small.Chunks = small.Records[:1], nil
	if _, err := f.svc.Save(ctx, owner, small, q); !errors.Is(err, ErrCharacterTooLarge) {
		t.Errorf("a save of a stored character over the limit gave %v", err)
	}
}

// When the files of a failed first save cannot be removed, the claim stays, so a new claim cannot reuse its id and
// load those files.
func TestFailedCleanupKeepsTheClaimOfTheFiles(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	flaky := &flakyBlobs{Blobs: f.blobs}
	svc := New(f.st, flaky, slog.New(slog.NewJSONHandler(io.Discard, nil)))
	flaky.failWrite = func(name string) bool { return name == "entry.json" }
	flaky.failRemove = true
	if _, err := svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy); err == nil {
		t.Fatal("the save hid the disk failure")
	}
	claim, err := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	if err != nil {
		t.Fatalf("the claim of the files left on disk went away: %v", err)
	}

	flaky.failWrite, flaky.failRemove = nil, false
	res, err := svc.Save(ctx, owner, upload(t, "eu-brumamar-nandu"), roomy)
	if err != nil {
		t.Fatal(err)
	}
	if after, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); after.ID != claim.ID || after.Steps != res.Steps {
		t.Errorf("the owner's next save did not adopt the claim: %+v", after)
	}
}

func TestSaveAgainAfterARecordWithTheMostKeys(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	character, err := os.ReadFile(filepath.Join(expectedDir, "eu-brumamar-nandu", "character.json"))
	if err != nil {
		t.Fatal(err)
	}
	rec := map[string]any{"t": 1793990000, "p": 1, "k": "zz", "addon": "Memories"}
	for i := 0; len(rec) < 48; i++ {
		rec["f"+strconv.Itoa(i)] = 1
	}
	raw, err := json.Marshal(map[string]any{"character": json.RawMessage(character), "journey": []any{rec}, "trail": []any{}})
	if err != nil {
		t.Fatal(err)
	}
	read := func() *validate.Upload {
		var buf bytes.Buffer
		zw := gzip.NewWriter(&buf)
		zw.Write(raw)
		zw.Close()
		lim := validate.Limits{MaxDecodedBytes: 64 << 20, MaxText: 512, MaxRecords: 500_000, MaxChunks: 50_000, MaxPoints: 20_000}
		up, problems := validate.Read(&buf, lim, time.Unix(1794000000, 0))
		if len(problems) > 0 {
			t.Fatalf("problems: %+v", problems)
		}
		return up
	}
	// The merge adds session to the record, so the stored record has one key more than an upload may send.
	for i := range 2 {
		if _, err := f.svc.Save(ctx, owner, read(), roomy); err != nil {
			t.Fatalf("save %d: %v", i+1, err)
		}
	}
}

// The merge drops an sn record whose note it carried onto an ss, so a save can end with fewer records than were
// stored; added must not go below 0.
func TestAddedIsNotNegativeWhenTheMergeDropsANote(t *testing.T) {
	f := newFixture(t)
	owner := f.key(1)
	records := func(withNotes bool) []validate.Record {
		ss := validate.Record{"addon": "Memories", "k": "ss", "p": nil, "t": json.Number("1793530000"), "file": "a.jpg"}
		if withNotes {
			ss["notes"] = []any{map[string]any{"source": "me", "note": "x"}}
		}
		sn := validate.Record{"addon": "Memories", "k": "sn", "p": nil, "t": json.Number("1793530001"), "source": "me", "note": "x"}
		return []validate.Record{ss, sn}
	}
	first := upload(t, "eu-brumamar-nandu")
	first.Records, first.Chunks = records(true), nil
	if _, err := f.svc.Save(ctx, owner, first, roomy); err != nil {
		t.Fatal(err)
	}
	second := upload(t, "eu-brumamar-nandu")
	second.Records, second.Chunks = records(false), nil
	res, err := f.svc.Save(ctx, owner, second, roomy)
	if err != nil {
		t.Fatal(err)
	}
	if res.Steps != 1 || res.Added != 0 {
		t.Errorf("steps = %d, added = %d; want 1 and 0", res.Steps, res.Added)
	}
}
