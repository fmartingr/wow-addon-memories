package api

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

const (
	expectedDir = "../../../testdata/expected"
	mergeDir    = "../../../testdata/merge"
	brumamar    = "wow/eu/brumamar/nandu"
	errantes    = "wow/eu/los-errantes/nandu"
)

var openMode = map[string]string{"MEMORIES_REGISTRATION": "open"}

func readFile(t testing.TB, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func decodeAny(t testing.TB, b []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

func jsonl(t testing.TB, b []byte) []any {
	t.Helper()
	out := []any{}
	for _, line := range bytes.Split(bytes.TrimSpace(b), []byte("\n")) {
		if len(line) > 0 {
			out = append(out, decodeAny(t, line))
		}
	}
	return out
}

// doc reads a folder of stored files as the JSON object of an upload.
func doc(t testing.TB, dir string) map[string]any {
	t.Helper()
	return map[string]any{
		"character": decodeAny(t, readFile(t, filepath.Join(dir, "character.json"))),
		"journey":   jsonl(t, readFile(t, filepath.Join(dir, "journey.jsonl"))),
		"trail":     jsonl(t, readFile(t, filepath.Join(dir, "trail.jsonl"))),
	}
}

func gz(t testing.TB, v any) []byte {
	t.Helper()
	raw, ok := v.([]byte)
	if !ok {
		var err error
		if raw, err = json.Marshal(v); err != nil {
			t.Fatal(err)
		}
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	zw.Write(raw)
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// upload sends the gzip of v, the JSON object of an upload, signed by c.
func (e *env) upload(c *client, v any) *httptest.ResponseRecorder {
	return e.uploadBytes(c, gz(e.t, v))
}

func (e *env) uploadBytes(c *client, body []byte) *httptest.ResponseRecorder {
	e.t.Helper()
	req := e.request(c, "POST", "/api/v1/characters", string(body))
	req.Header.Set("Content-Encoding", "gzip")
	return e.serve(req)
}

func (e *env) uploadDir(c *client, dir string) *httptest.ResponseRecorder {
	e.t.Helper()
	return e.upload(c, doc(e.t, dir))
}

type uploadAnswer struct {
	Error    string `json:"error"`
	Message  string `json:"message"`
	Path     string `json:"path"`
	URL      string `json:"url"`
	Steps    int64  `json:"steps"`
	Added    int64  `json:"added"`
	Problems []struct {
		File   string `json:"file"`
		Line   int    `json:"line"`
		Field  string `json:"field"`
		Reason string `json:"reason"`
	} `json:"problems"`
}

func (e *env) ok(rec *httptest.ResponseRecorder) uploadAnswer {
	e.t.Helper()
	var a uploadAnswer
	if err := json.Unmarshal(rec.Body.Bytes(), &a); err != nil || rec.Code != http.StatusOK {
		e.t.Fatalf("upload: %d %s", rec.Code, rec.Body)
	}
	return a
}

func (e *env) fail(rec *httptest.ResponseRecorder, status int, code string) uploadAnswer {
	e.t.Helper()
	expectError(e.t, rec, status, code)
	var a uploadAnswer
	json.Unmarshal(rec.Body.Bytes(), &a)
	return a
}

func (e *env) claim(path string) (store.Claim, error) {
	p := strings.Split(path, "/")
	return e.st.ClaimByPath(bg, p[0], p[1], p[2], p[3])
}

// stored returns a stored file of the claim at path, or nil when there is none.
func (e *env) stored(path, name string) []byte {
	e.t.Helper()
	c, err := e.claim(path)
	if err != nil {
		e.t.Fatalf("claim %s: %v", path, err)
	}
	b, err := os.ReadFile(filepath.Join(e.data, "characters", itoa(c.ID), name))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		e.t.Fatal(err)
	}
	return b
}

func itoa(n int64) string { return strconv.FormatInt(n, 10) }

// approved registers a client and approves its screenshots.
// approved registers c with an invite, so that the key is not an open key, and approves its screenshots.
func (e *env) approved(c *client) {
	e.t.Helper()
	e.registered(c)
	k, err := e.st.KeyByPublic(bg, c.public())
	if err != nil {
		e.t.Fatal(err)
	}
	if err := e.st.SetScreenshots(bg, k.ID, store.ShotsApproved); err != nil {
		e.t.Fatal(err)
	}
}

func TestUploadStoresEachExpectedCharacter(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approved(c)
	index := decodeAny(t, readFile(t, filepath.Join(expectedDir, "index.json"))).(map[string]any)["characters"].([]any)

	for _, tc := range []struct{ id, path string }{{"eu-brumamar-nandu", brumamar}, {"eu-los-errantes-nandu", errantes}} {
		a := e.ok(e.uploadDir(c, filepath.Join(expectedDir, tc.id)))
		src := filepath.Join(expectedDir, tc.id)
		if a.Path != tc.path || a.URL != "http://localhost:8080/"+tc.path+"/" || a.Steps != a.Added || a.Steps == 0 {
			t.Errorf("%s: answer %+v", tc.id, a)
		}
		for _, name := range []string{"character.json", "journey.jsonl", "trail.jsonl"} {
			if got := e.stored(tc.path, name); !bytes.Equal(got, readFile(t, filepath.Join(src, name))) {
				t.Errorf("%s %s differs from the source:\n got %s", tc.id, name, got)
			}
		}

		got := decodeAny(t, e.stored(tc.path, "entry.json")).(map[string]any)
		for k, want := range map[string]any{"id": tc.path, "path": ".", "character": "character.json", "journey": "journey.jsonl", "trail": "trail.jsonl"} {
			if got[k] != want {
				t.Errorf("%s entry %s = %v, want %v", tc.id, k, got[k], want)
			}
			delete(got, k)
		}
		var want map[string]any
		for _, v := range index {
			if v.(map[string]any)["id"] == tc.id {
				want = v.(map[string]any)
			}
		}
		for _, k := range []string{"id", "path", "character", "journey", "trail"} {
			delete(want, k)
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s entry differs from its index.json entry:\n got %v\nwant %v", tc.id, got, want)
		}
		claim, err := e.claim(tc.path)
		if err != nil || claim.Steps != a.Steps || claim.DataBytes <= 0 || claim.GUID != want["guid"] {
			t.Errorf("%s claim = %+v, %v", tc.id, claim, err)
		}
	}
	me := e.do(c, "GET", "/api/v1/me", "")
	if got := decode(t, me); len(got.Characters) != 2 {
		t.Errorf("me lists %d characters, want 2", len(got.Characters))
	}
}

func TestUploadWithoutScreenshotApprovalDropsTheScreenshotField(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered2(c)
	a := e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	if a.Steps != 15 {
		t.Fatalf("steps = %d, want 15", a.Steps)
	}
	if got := e.stored(brumamar, "journey.jsonl"); bytes.Contains(got, []byte(`"screenshot"`)) {
		t.Error("the stored journey names a screenshot that the key may not upload")
	}
	if entry := decodeAny(t, e.stored(brumamar, "entry.json")).(map[string]any); entry["screenshots"].(json.Number) != "0" {
		t.Errorf("entry screenshots = %v, want 0", entry["screenshots"])
	}
}

func TestScreenshotsStayWhenApprovalIsLost(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approved(c)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	e.ok(e.uploadDir(c, dir))
	k, _ := e.st.KeyByPublic(bg, c.public())
	if err := e.st.SetScreenshots(bg, k.ID, store.ShotsDenied); err != nil {
		t.Fatal(err)
	}
	if a := e.ok(e.uploadDir(c, dir)); a.Added != 0 {
		t.Errorf("added = %d, want 0", a.Added)
	}
	if got := e.stored(brumamar, "journey.jsonl"); !bytes.Equal(got, readFile(t, filepath.Join(dir, "journey.jsonl"))) {
		t.Errorf("the old screenshot fields did not stay:\n%s", got)
	}
}

func TestSecondUploadOfTheSameDataChangesNoByte(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approved(c)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	e.ok(e.uploadDir(c, dir))
	before := map[string][]byte{}
	for _, n := range []string{"character.json", "journey.jsonl", "trail.jsonl", "entry.json"} {
		before[n] = e.stored(brumamar, n)
	}
	a := e.ok(e.uploadDir(c, dir))
	if a.Added != 0 || a.Steps != 15 {
		t.Errorf("answer %+v, want 15 steps and 0 added", a)
	}
	for n, b := range before {
		if !bytes.Equal(e.stored(brumamar, n), b) {
			t.Errorf("%s changed on the second upload", n)
		}
	}
}

func TestSecondUploadMergesIntoTheStoredData(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approved(c)
	old := e.ok(e.uploadDir(c, filepath.Join(mergeDir, "old")))
	a := e.ok(e.uploadDir(c, filepath.Join(mergeDir, "fresh")))
	want := jsonl(t, readFile(t, filepath.Join(mergeDir, "expected", "journey.jsonl")))
	if a.Steps != int64(len(want)) || a.Added != a.Steps-old.Steps || a.Added <= 0 {
		t.Errorf("answer %+v after %+v, want %d steps", a, old, len(want))
	}
	path := "wow/eu/brumamar/nandu"
	for _, name := range []string{"character.json", "journey.jsonl", "trail.jsonl"} {
		if got := e.stored(path, name); !bytes.Equal(got, readFile(t, filepath.Join(mergeDir, "expected", name))) {
			t.Errorf("%s differs from testdata/merge/expected:\n got %s", name, got)
		}
	}
}

func TestUploadWithFewerRecordsKeepsTheStoredOnes(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approved(c)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	e.ok(e.uploadDir(c, dir))
	d := doc(t, dir)
	d["journey"] = d["journey"].([]any)[:3]
	d["trail"] = []any{}
	a := e.ok(e.upload(c, d))
	if a.Steps != 15 || a.Added != 0 {
		t.Errorf("answer %+v, want 15 steps and 0 added", a)
	}
	if got := e.stored(brumamar, "journey.jsonl"); !bytes.Equal(got, readFile(t, filepath.Join(dir, "journey.jsonl"))) {
		t.Error("the journey lost records")
	}
	if got := e.stored(brumamar, "trail.jsonl"); !bytes.Equal(got, readFile(t, filepath.Join(dir, "trail.jsonl"))) {
		t.Error("the trail lost chunks")
	}
}

func TestUploadErrors(t *testing.T) {
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")

	t.Run("not registered", func(t *testing.T) {
		e := newEnv(t, openMode)
		e.fail(e.uploadDir(newClient(1), dir), http.StatusUnauthorized, "not_registered")
	})
	t.Run("revoked", func(t *testing.T) {
		e := newEnv(t, openMode)
		c := newClient(1)
		e.registered2(c)
		e.revoke(c)
		e.fail(e.uploadDir(c, dir), http.StatusForbidden, "key_revoked")
	})
	t.Run("not gzip by header", func(t *testing.T) {
		e := newEnv(t, openMode)
		c := newClient(1)
		e.registered2(c)
		rec := e.serve(e.request(c, "POST", "/api/v1/characters", string(gz(t, doc(t, dir)))))
		e.fail(rec, http.StatusUnsupportedMediaType, "gzip_required")
	})
	t.Run("not gzip data", func(t *testing.T) {
		e := newEnv(t, openMode)
		c := newClient(1)
		e.registered2(c)
		a := e.fail(e.uploadBytes(c, []byte(`{"character":{}}`)), http.StatusUnprocessableEntity, "invalid")
		if len(a.Problems) != 1 || !strings.Contains(a.Problems[0].Reason, "gzip") {
			t.Errorf("problems = %+v", a.Problems)
		}
	})
	t.Run("invalid data stores nothing", func(t *testing.T) {
		e := newEnv(t, openMode)
		c := newClient(1)
		e.registered2(c)
		d := doc(t, dir)
		for i := range d["journey"].([]any) {
			d["journey"].([]any)[i].(map[string]any)["t"] = "soon"
		}
		a := e.fail(e.upload(c, d), http.StatusUnprocessableEntity, "invalid")
		if n := len(a.Problems); n == 0 || n > 20 {
			t.Errorf("%d problems, want 1 to 20", n)
		}
		if p := a.Problems[0]; p.File != "journey" || p.Line != 1 || p.Field != "t" || p.Reason == "" {
			t.Errorf("first problem = %+v", p)
		}
		if _, err := e.claim(brumamar); !errors.Is(err, store.ErrNotFound) {
			t.Errorf("a rejected upload left a claim: %v", err)
		}
		entries, _ := os.ReadDir(filepath.Join(e.data, "characters"))
		if len(entries) != 0 {
			t.Errorf("a rejected upload left %d folders", len(entries))
		}
	})
	t.Run("too large after unpacking", func(t *testing.T) {
		e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_DECODED_BYTES": "2000"})
		c := newClient(1)
		e.registered2(c)
		e.fail(e.uploadDir(c, dir), http.StatusRequestEntityTooLarge, "too_large")
	})
	t.Run("too large request", func(t *testing.T) {
		e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_UPLOAD_BYTES": "200"})
		c := newClient(1)
		e.registered2(c)
		e.fail(e.uploadDir(c, dir), http.StatusRequestEntityTooLarge, "too_large")
	})
	t.Run("another key owns the path", func(t *testing.T) {
		e := newEnv(t, openMode)
		a, b := newClient(1), newClient(2)
		e.registered2(a)
		e.registered2(b)
		e.ok(e.uploadDir(a, dir))
		before := e.stored(brumamar, "journey.jsonl")
		e.fail(e.uploadDir(b, filepath.Join(mergeDir, "fresh")), http.StatusConflict, "claimed")
		if !bytes.Equal(e.stored(brumamar, "journey.jsonl"), before) {
			t.Error("a refused upload changed the stored journey")
		}
		if c, _ := e.claim(brumamar); c.KeyID == 0 || len(e.claimsOf(b)) != 0 {
			t.Errorf("claim %+v", c)
		}
	})
	t.Run("another character GUID", func(t *testing.T) {
		e := newEnv(t, openMode)
		c := newClient(1)
		e.registered2(c)
		e.ok(e.uploadDir(c, dir))
		d := doc(t, dir)
		d["character"].(map[string]any)["guid"] = "Player-1234-0ABCDEF1"
		e.fail(e.upload(c, d), http.StatusConflict, "guid_mismatch")
	})
	t.Run("a name that cannot make an address", func(t *testing.T) {
		e := newEnv(t, openMode)
		c := newClient(1)
		e.registered2(c)
		d := doc(t, dir)
		d["character"].(map[string]any)["realm"] = "!!!"
		a := e.fail(e.upload(c, d), http.StatusUnprocessableEntity, "invalid")
		if len(a.Problems) != 1 || a.Problems[0].Field != "realm" {
			t.Errorf("problems = %+v", a.Problems)
		}
	})
}

func (e *env) claimsOf(c *client) []store.Claim {
	e.t.Helper()
	k, err := e.st.KeyByPublic(bg, c.public())
	if err != nil {
		e.t.Fatal(err)
	}
	claims, err := e.st.ClaimsOfKey(bg, k.ID)
	if err != nil {
		e.t.Fatal(err)
	}
	return claims
}

func TestCharacterQuota(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CHARACTERS_PER_KEY": "1"})
	c := newClient(1)
	e.registered2(c)
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	a := e.fail(e.uploadDir(c, filepath.Join(expectedDir, "eu-los-errantes-nandu")), http.StatusInsufficientStorage, "quota")
	if !strings.Contains(a.Message, "most characters") {
		t.Errorf("message = %q", a.Message)
	}
	if _, err := e.claim(errantes); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("the refused character left a claim: %v", err)
	}
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))

	other := newClient(2)
	e.registered2(other)
	e.ok(e.uploadDir(other, filepath.Join(expectedDir, "eu-los-errantes-nandu")))
}

// Each save decodes the stored character, so one character may not grow past twice the largest decoded upload.
func TestCharacterSizeLimit(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered2(c)
	e.ok(e.uploadDir(c, filepath.Join(mergeDir, "old")))
	path := "wow/eu/brumamar/nandu"
	claim, _ := e.claim(path)
	journey := e.stored(path, "journey.jsonl")

	small := doc(t, filepath.Join(mergeDir, "old"))
	small["journey"], small["trail"] = []any{}, []any{}
	e.cfg.MaxDecodedBytes = claim.DataBytes/2 - 1
	e.start()
	a := e.fail(e.upload(c, small), http.StatusRequestEntityTooLarge, "too_large")
	if !strings.Contains(a.Message, "one character") {
		t.Errorf("message = %q", a.Message)
	}
	if !bytes.Equal(e.stored(path, "journey.jsonl"), journey) {
		t.Error("the refused upload changed the stored journey")
	}
	if maxCharacterBytes(64) != 128 {
		t.Errorf("maxCharacterBytes(64) = %d, want 128", maxCharacterBytes(64))
	}
}

func TestDataQuota(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered(c)
	e.ok(e.uploadDir(c, filepath.Join(mergeDir, "old")))
	path := "wow/eu/brumamar/nandu"
	claim, _ := e.claim(path)
	before := map[string][]byte{}
	for _, n := range []string{"character.json", "journey.jsonl", "trail.jsonl", "entry.json"} {
		before[n] = e.stored(path, n)
	}

	e.cfg.MaxDataBytesPerKey = claim.DataBytes + 10
	e.start()
	a := e.fail(e.uploadDir(c, filepath.Join(mergeDir, "fresh")), http.StatusInsufficientStorage, "quota")
	if !strings.Contains(a.Message, "most data") {
		t.Errorf("message = %q", a.Message)
	}
	for n, b := range before {
		if !bytes.Equal(e.stored(path, n), b) {
			t.Errorf("%s changed although the upload went over the quota", n)
		}
	}
	if after, _ := e.claim(path); after.Steps != claim.Steps || after.DataBytes != claim.DataBytes {
		t.Errorf("claim after = %+v, before = %+v", after, claim)
	}

	// Another character of the same key counts against the same limit, and leaves no claim behind.
	e.fail(e.uploadDir(c, filepath.Join(expectedDir, "eu-los-errantes-nandu")), http.StatusInsufficientStorage, "quota")
	if _, err := e.claim(errantes); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("the refused character left a claim: %v", err)
	}
	if entries, _ := os.ReadDir(filepath.Join(e.data, "characters")); len(entries) != 1 {
		t.Errorf("%d folders, want 1", len(entries))
	}
}

// failingBlobs fails the Write of one file name.
type failingBlobs struct {
	store.Blobs
	name string
	mu   sync.Mutex
	fail bool
}

func (f *failingBlobs) Write(ctx context.Context, path string, r io.Reader) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fail && strings.HasSuffix(path, "/"+f.name) {
		return errors.New("disk full")
	}
	return f.Blobs.Write(ctx, path, r)
}

func TestDiskFailureKeepsTheOldFilesAndLeavesNoEmptyClaim(t *testing.T) {
	for _, name := range []string{"journey.jsonl", "character.json", "entry.json"} {
		t.Run(name, func(t *testing.T) {
			e := newEnv(t, openMode)
			fb := &failingBlobs{name: name}
			e.wrap = func(b store.Blobs) store.Blobs { fb.Blobs = b; return fb }
			e.start()
			c := newClient(1)
			e.registered2(c)

			fb.fail = true
			rec := e.uploadDir(c, filepath.Join(mergeDir, "old"))
			a := e.fail(rec, http.StatusInternalServerError, "internal")
			if strings.Contains(a.Message, "disk full") || strings.Contains(e.logs.String(), "Player-") {
				t.Errorf("message %q or the logs show internals or data: %s", a.Message, e.logs)
			}
			if _, err := e.claim("wow/eu/brumamar/nandu"); !errors.Is(err, store.ErrNotFound) {
				t.Errorf("a failed first upload left a claim: %v", err)
			}
			if entries, _ := os.ReadDir(filepath.Join(e.data, "characters")); len(entries) != 0 {
				t.Errorf("a failed first upload left %d folders", len(entries))
			}

			fb.fail = false
			e.ok(e.uploadDir(c, filepath.Join(mergeDir, "old")))
			path := "wow/eu/brumamar/nandu"
			claim, _ := e.claim(path)
			before := map[string][]byte{}
			for _, n := range []string{"character.json", "journey.jsonl", "trail.jsonl", "entry.json"} {
				before[n] = e.stored(path, n)
			}
			fb.fail = true
			e.fail(e.uploadDir(c, filepath.Join(mergeDir, "fresh")), http.StatusInternalServerError, "internal")
			for n, b := range before {
				if !bytes.Equal(e.stored(path, n), b) {
					t.Errorf("%s changed although the write failed", n)
				}
			}
			if after, _ := e.claim(path); after.Steps != claim.Steps || after.DataBytes != claim.DataBytes {
				t.Errorf("claim after = %+v, before = %+v", after, claim)
			}
		})
	}
}

func TestDeleteByOwnerFreesThePath(t *testing.T) {
	e := newEnv(t, openMode)
	a, b := newClient(1), newClient(2)
	e.approved(a)
	e.approved(b)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	e.ok(e.uploadDir(a, dir))
	claim, _ := e.claim(brumamar)
	target := "/api/v1/characters/" + brumamar

	e.fail(e.do(b, "DELETE", target, ""), http.StatusNotFound, "not_found")
	if _, err := e.claim(brumamar); err != nil {
		t.Fatalf("a foreign delete removed the claim: %v", err)
	}
	if rec := e.do(a, "DELETE", target, ""); rec.Code != http.StatusNoContent || rec.Body.Len() != 0 {
		t.Fatalf("delete: %d %s", rec.Code, rec.Body)
	}
	if _, err := e.claim(brumamar); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("the claim stayed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(e.data, "characters", itoa(claim.ID))); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the files stayed: %v", err)
	}
	e.fail(e.do(a, "DELETE", target, ""), http.StatusNotFound, "not_found")

	e.ok(e.uploadDir(b, dir))
	if c, err := e.claim(brumamar); err != nil || c.KeyID == claim.KeyID {
		t.Errorf("the other key did not take the path: %+v, %v", c, err)
	}
	if got := e.stored(brumamar, "journey.jsonl"); !bytes.Equal(got, readFile(t, filepath.Join(dir, "journey.jsonl"))) {
		t.Error("the new owner's data is not the upload alone")
	}
}

func TestDeleteRoutesRejectBadSegmentsAndStrangers(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered2(c)
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	for _, target := range []string{
		"/api/v1/characters/wow/EU/brumamar/nandu",
		"/api/v1/characters/wow/eu/..%2f..%2fx/nandu",
		"/api/v1/characters/wow/eu/brumamar/na%20ndu",
		"/api/v1/characters/wow/eu/-/nandu",
		"/api/v1/characters/wow/eu/brumamar/other",
	} {
		e.fail(e.do(c, "DELETE", target, ""), http.StatusNotFound, "not_found")
	}
	if _, err := e.claim(brumamar); err != nil {
		t.Errorf("a bad delete removed the character: %v", err)
	}
	e.fail(e.do(newClient(9), "DELETE", "/api/v1/characters/"+brumamar, ""), http.StatusUnauthorized, "not_registered")
}

func TestConcurrentUploadsOfOnePathLoseNoRecord(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CONCURRENT_UPLOADS": "4"})
	c := newClient(1)
	e.approved(c)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	full := doc(t, dir)
	journey := full["journey"].([]any)

	var reqs []*http.Request
	for i := range journey {
		d := doc(t, dir)
		d["journey"] = journey[i : i+1]
		d["trail"] = []any{}
		req := e.request(c, "POST", "/api/v1/characters", string(gz(t, d)))
		req.Header.Set("Content-Encoding", "gzip")
		reqs = append(reqs, req)
	}
	recs := make([]*httptest.ResponseRecorder, len(reqs))
	var wg sync.WaitGroup
	for i := range reqs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			recs[i] = e.serve(reqs[i])
		}()
	}
	wg.Wait()
	for _, rec := range recs {
		e.ok(rec)
	}
	e.ok(e.uploadDir(c, dir))

	// One record per upload, then the whole upload: the stored journey is the whole journey, in the stored order.
	claim, _ := e.claim(brumamar)
	if claim.Steps != int64(len(journey)) {
		t.Errorf("steps = %d, want %d", claim.Steps, len(journey))
	}
	if got := jsonl(t, e.stored(brumamar, "journey.jsonl")); len(got) != len(journey) {
		t.Errorf("%d records stored, want %d", len(got), len(journey))
	}
	if len(e.claimsOf(c)) != 1 {
		t.Errorf("%d claims, want 1", len(e.claimsOf(c)))
	}
}

func TestTwoKeysRacingForOnePathGetOneWinner(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CONCURRENT_UPLOADS": "4"})
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	clients := []*client{newClient(1), newClient(2), newClient(3), newClient(4)}
	reqs := make([]*http.Request, len(clients))
	for i, c := range clients {
		e.registered2(c)
		reqs[i] = e.request(c, "POST", "/api/v1/characters", string(gz(t, doc(t, dir))))
		reqs[i].Header.Set("Content-Encoding", "gzip")
	}
	recs := make([]*httptest.ResponseRecorder, len(clients))
	var wg sync.WaitGroup
	for i := range reqs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			recs[i] = e.serve(reqs[i])
		}()
	}
	wg.Wait()
	wins, conflicts := 0, 0
	for _, rec := range recs {
		switch rec.Code {
		case http.StatusOK:
			wins++
		case http.StatusConflict:
			conflicts++
		default:
			t.Errorf("status %d: %s", rec.Code, rec.Body)
		}
	}
	if wins != 1 || conflicts != len(clients)-1 {
		t.Errorf("%d winners and %d conflicts, want 1 and %d", wins, conflicts, len(clients)-1)
	}
}

func TestUploadsAndDeletesOfOnePathStayConsistent(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CONCURRENT_UPLOADS": "4"})
	c := newClient(1)
	e.approved(c)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	var reqs []*http.Request
	for range 6 {
		up := e.request(c, "POST", "/api/v1/characters", string(gz(t, doc(t, dir))))
		up.Header.Set("Content-Encoding", "gzip")
		reqs = append(reqs, up, e.request(c, "DELETE", "/api/v1/characters/"+brumamar, ""))
	}
	var wg sync.WaitGroup
	for _, req := range reqs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			rec := e.serve(req)
			if rec.Code != http.StatusOK && rec.Code != http.StatusNoContent && rec.Code != http.StatusNotFound {
				t.Errorf("%s: status %d: %s", req.Method, rec.Code, rec.Body)
			}
		}()
	}
	wg.Wait()

	// Whatever the order was, the claim and the files agree: both are there or both are gone.
	claims := e.claimsOf(c)
	entries, _ := os.ReadDir(filepath.Join(e.data, "characters"))
	if len(claims) != len(entries) {
		t.Fatalf("%d claims and %d folders", len(claims), len(entries))
	}
	if len(claims) == 1 {
		if got := e.stored(brumamar, "journey.jsonl"); !bytes.Equal(got, readFile(t, filepath.Join(dir, "journey.jsonl"))) {
			t.Error("the stored journey is not the uploaded one")
		}
	}
}

func TestUploadWaitsForASlotThenAnswersBusy(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CONCURRENT_UPLOADS": "1"})
	c := newClient(1)
	e.registered2(c)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")

	e.api.slots <- struct{}{}
	e.api.uploadWait = 30 * time.Millisecond
	rec := e.uploadDir(c, dir)
	a := e.fail(rec, http.StatusServiceUnavailable, "busy")
	if rec.Header().Get("Retry-After") == "" || !strings.Contains(a.Message, "try again") {
		t.Errorf("Retry-After %q, message %q", rec.Header().Get("Retry-After"), a.Message)
	}
	if _, err := e.claim(brumamar); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("a refused upload left a claim: %v", err)
	}

	e.api.uploadWait = 5 * time.Second
	req := e.request(c, "POST", "/api/v1/characters", string(gz(t, doc(t, dir))))
	req.Header.Set("Content-Encoding", "gzip")
	done := make(chan *httptest.ResponseRecorder)
	go func() { done <- e.serve(req) }()
	select {
	case <-done:
		t.Fatal("the upload ran while the only slot was taken")
	case <-time.After(50 * time.Millisecond):
	}
	<-e.api.slots
	select {
	case rec := <-done:
		e.ok(rec)
	case <-time.After(5 * time.Second):
		t.Fatal("the upload did not run after the slot was free")
	}
	if len(e.api.slots) != 0 {
		t.Errorf("%d slots still taken after the upload", len(e.api.slots))
	}
}

func TestUploadGivesUpWhenTheClientLeavesWhileWaiting(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CONCURRENT_UPLOADS": "1"})
	c := newClient(1)
	e.registered2(c)
	e.api.slots <- struct{}{}
	req := e.request(c, "POST", "/api/v1/characters", string(gz(t, doc(t, filepath.Join(expectedDir, "eu-brumamar-nandu")))))
	req.Header.Set("Content-Encoding", "gzip")
	e.api.uploadWait = 5 * time.Second
	ctx, cancel := context.WithCancel(req.Context())
	time.AfterFunc(50*time.Millisecond, cancel)
	rec := e.serve(req.WithContext(ctx))
	if rec.Body.Len() != 0 {
		t.Errorf("answered a client that left: %d %s", rec.Code, rec.Body)
	}
	if len(e.api.slots) != 1 {
		t.Errorf("slots taken = %d, want only the one the test holds", len(e.api.slots))
	}
}

func TestSlotsComeBackAfterEachOutcome(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered2(c)
	e.fail(e.uploadBytes(c, []byte("junk")), http.StatusUnprocessableEntity, "invalid")
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	if len(e.api.slots) != 0 {
		t.Errorf("%d slots still taken", len(e.api.slots))
	}
}
