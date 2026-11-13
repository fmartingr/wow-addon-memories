package api

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"errors"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/images"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

const (
	imagesDir = "../images/testdata"
	shotA     = "WoWScrnShot_110126_114820.jpg"
	shotB     = "WoWScrnShot_110126_115001.jpg"
)

func shotTarget(path, file string) string {
	return "/api/v1/characters/" + path + "/screenshots/" + file
}

func (e *env) putShot(c *client, path, file string, body []byte) *httptest.ResponseRecorder {
	e.t.Helper()
	return e.do(c, "PUT", shotTarget(path, file), string(body))
}

// shotDoc is the brumamar upload with the screenshot names of its two ss records replaced by names.
func shotDoc(t testing.TB, names ...string) map[string]any {
	t.Helper()
	d := doc(t, filepath.Join(expectedDir, "eu-brumamar-nandu"))
	i := 0
	for _, r := range d["journey"].([]any) {
		rec := r.(map[string]any)
		if rec["k"] == "ss" && i < len(names) {
			rec["screenshot"] = "screenshots/" + names[i]
			i++
		}
	}
	if i != len(names) {
		t.Fatalf("the fixture has %d ss records, the test names %d", i, len(names))
	}
	return d
}

// approvedWithShots registers an approved key and uploads brumamar, so that the two screenshots are named.
func (e *env) approvedWithShots(c *client) {
	e.t.Helper()
	e.approved(c)
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
}

func (e *env) storedShot(path, file string) []byte {
	e.t.Helper()
	return e.stored(path, "screenshots/"+file)
}

func TestScreenshotStoresACleanCopy(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	src := readFile(t, filepath.Join(imagesDir, "exif-gps.jpg"))

	rec := e.putShot(c, brumamar, shotA, src)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status %d %s", rec.Code, rec.Body)
	}
	got := e.storedShot(brumamar, shotA)
	if got == nil || bytes.Contains(got, []byte("Exif")) {
		t.Fatalf("stored file is missing or keeps EXIF data (%d bytes)", len(got))
	}
	if _, format, err := image.Decode(bytes.NewReader(got)); err != nil || format != "jpeg" {
		t.Errorf("stored file: %v, %v", format, err)
	}
	claim, _ := e.claim(brumamar)
	if claim.ShotBytes != int64(len(got)) {
		t.Errorf("shot_bytes = %d, want %d", claim.ShotBytes, len(got))
	}
	sh, err := e.st.ShotOf(bg, claim.ID, shotA)
	want := sha256.Sum256(src)
	if err != nil || !bytes.Equal(sh.UploadSHA256, want[:]) || sh.Bytes != int64(len(got)) {
		t.Errorf("shot row = %+v, %v", sh, err)
	}
}

func TestScreenshotSameBytesGive200AndChangeNothing(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	src := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	if rec := e.putShot(c, brumamar, shotA, src); rec.Code != http.StatusCreated {
		t.Fatalf("first: %d %s", rec.Code, rec.Body)
	}
	before := e.storedShot(brumamar, shotA)
	claim, _ := e.claim(brumamar)
	file := filepath.Join(e.data, "characters", itoa(claim.ID), "screenshots", shotA)
	infoBefore, _ := os.Stat(file)

	if rec := e.putShot(c, brumamar, shotA, src); rec.Code != http.StatusOK {
		t.Fatalf("same bytes: %d %s", rec.Code, rec.Body)
	}
	infoAfter, _ := os.Stat(file)
	if !bytes.Equal(e.storedShot(brumamar, shotA), before) || !os.SameFile(infoBefore, infoAfter) {
		t.Error("the same upload rewrote the file")
	}
	after, _ := e.claim(brumamar)
	if after.ShotBytes != claim.ShotBytes {
		t.Errorf("shot_bytes %d -> %d", claim.ShotBytes, after.ShotBytes)
	}

	other := readFile(t, filepath.Join(imagesDir, "exif-gps.jpg"))
	if rec := e.putShot(c, brumamar, shotA, other); rec.Code != http.StatusCreated {
		t.Fatalf("other bytes: %d %s", rec.Code, rec.Body)
	}
	if after, _ := e.claim(brumamar); after.ShotBytes != int64(len(e.storedShot(brumamar, shotA))) {
		t.Errorf("shot_bytes = %d after a replace, want the size of the one file", after.ShotBytes)
	}
}

func TestScreenshotStoredAgainWhenTheFileIsGone(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	src := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	e.putShot(c, brumamar, shotA, src)
	claim, _ := e.claim(brumamar)
	if err := os.Remove(filepath.Join(e.data, "characters", itoa(claim.ID), "screenshots", shotA)); err != nil {
		t.Fatal(err)
	}
	if rec := e.putShot(c, brumamar, shotA, src); rec.Code != http.StatusCreated || e.storedShot(brumamar, shotA) == nil {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
}

func TestScreenshotPNGStaysPNG(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approved(c)
	name := "WoWScrnShot_110126_114820.png"
	e.ok(e.upload(c, shotDoc(t, name)))
	rec := e.putShot(c, brumamar, name, readFile(t, filepath.Join(imagesDir, "text-chunk.png")))
	if rec.Code != http.StatusCreated {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	got := e.storedShot(brumamar, name)
	if _, format, err := image.DecodeConfig(bytes.NewReader(got)); err != nil || format != "png" || bytes.Contains(got, []byte("secret-note")) {
		t.Errorf("stored: %v, %v", format, err)
	}
}

func TestScreenshotErrors(t *testing.T) {
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	for _, tc := range []struct {
		name   string
		names  []string
		target string // overrides the default path and file
		file   string
		body   []byte
		status int
		code   string
	}{
		{name: "not an image", file: shotA, body: []byte("hello"), status: 415, code: "unsupported_image"},
		{name: "empty body", file: shotA, body: nil, status: 415, code: "unsupported_image"},
		{name: "truncated jpeg", file: shotA, body: small[:300], status: 415, code: "unsupported_image"},
		{name: "png content in a jpg name", file: shotA, body: readFile(t, filepath.Join(imagesDir, "small.png")), status: 415, code: "unsupported_image"},
		{name: "jpeg content in a png name", names: []string{"WoWScrnShot_110126_114820.png"}, file: "WoWScrnShot_110126_114820.png",
			body: readFile(t, filepath.Join(imagesDir, "jpeg-named.png")), status: 415, code: "unsupported_image"},
		{name: "tga", names: []string{"WoWScrnShot_110126_114820.tga"}, file: "WoWScrnShot_110126_114820.tga",
			body: readFile(t, filepath.Join(imagesDir, "small.tga")), status: 415, code: "unsupported_image"},
		{name: "pixel bomb header", names: []string{"WoWScrnShot_110126_114820.png"}, file: "WoWScrnShot_110126_114820.png",
			body: readFile(t, filepath.Join(imagesDir, "bomb.png")), status: 413, code: "too_large"},
		{name: "not named by a record", file: "WoWScrnShot_110126_999999.jpg", body: small, status: 404, code: "not_referenced"},
		{name: "name with another extension", file: "WoWScrnShot_110126_114820.png", body: small, status: 404, code: "not_referenced"},
		{name: "bad file name", file: "evil.jpg", body: small, status: 404, code: "not_referenced"},
		{name: "traversal in the file name", file: "..%2f..%2fcharacter.json", body: small, status: 404, code: "not_referenced"},
		{name: "unknown character", target: shotTarget("wow/eu/brumamar/other", shotA), body: small, status: 404, code: "not_found"},
		{name: "bad path segment", target: shotTarget("wow/EU/brumamar/nandu", shotA), body: small, status: 404, code: "not_found"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			e := newEnv(t, openMode)
			c := newClient(1)
			e.approved(c)
			if tc.names != nil {
				e.ok(e.upload(c, shotDoc(t, tc.names...)))
			} else {
				e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
			}
			target := tc.target
			if target == "" {
				target = shotTarget(brumamar, tc.file)
			}
			a := expectError(t, e.do(c, "PUT", target, string(tc.body)), tc.status, tc.code)
			claim, _ := e.claim(brumamar)
			if claim.ShotBytes != 0 {
				t.Errorf("a refused screenshot counted %d bytes", claim.ShotBytes)
			}
			if entries, _ := os.ReadDir(filepath.Join(e.data, "characters", itoa(claim.ID))); len(entries) != 4 {
				t.Errorf("a refused screenshot left files: %v", entries)
			}
			if a.Message == "" {
				t.Error("no message")
			}
		})
	}
}

func TestScreenshotNeedsApprovalAndOwnership(t *testing.T) {
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	e := newEnv(t, openMode)
	owner, other, plain := newClient(1), newClient(2), newClient(3)
	e.approvedWithShots(owner)
	e.approved(other)
	e.registered2(plain)

	e.fail(e.putShot(newClient(9), brumamar, shotA, small), http.StatusUnauthorized, "not_registered")
	e.fail(e.putShot(other, brumamar, shotA, small), http.StatusNotFound, "not_found")
	e.fail(e.putShot(plain, brumamar, shotA, small), http.StatusNotFound, "not_found")

	for _, state := range []string{store.ShotsDenied, store.ShotsPending, "none"} {
		k, _ := e.st.KeyByPublic(bg, owner.public())
		if err := e.st.SetScreenshots(bg, k.ID, state); err != nil {
			t.Fatal(err)
		}
		e.fail(e.putShot(owner, brumamar, shotA, small), http.StatusForbidden, "screenshots_not_approved")
	}
	claim, _ := e.claim(brumamar)
	if e.storedShot(brumamar, shotA) != nil || claim.ShotBytes != 0 {
		t.Error("a refused key stored a screenshot")
	}

	e.revoke(owner)
	e.fail(e.putShot(owner, brumamar, shotA, small), http.StatusForbidden, "key_revoked")
}

func TestKeyWithoutApprovalHasNoScreenshotRecordToUpload(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered(c)
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	e.fail(e.putShot(c, brumamar, shotA, readFile(t, filepath.Join(imagesDir, "small.jpg"))), http.StatusForbidden, "screenshots_not_approved")
}

func TestScreenshotChecksTheCurrentStoredJourney(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))

	// An upload that no longer names the screenshots keeps the stored links, so the files are still wanted.
	d := doc(t, filepath.Join(expectedDir, "eu-brumamar-nandu"))
	for _, r := range d["journey"].([]any) {
		delete(r.(map[string]any), "screenshot")
	}
	e.ok(e.upload(c, d))
	if rec := e.putShot(c, brumamar, shotB, small); rec.Code != http.StatusCreated {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}

	// The stored journey of another character names nothing of this one.
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-los-errantes-nandu")))
	e.fail(e.putShot(c, errantes, shotA, small), http.StatusNotFound, "not_referenced")
}

// A record of an unknown kind may carry any key as text; only the exact screenshot key names a file.
func TestScreenshotOtherCaseKeyIsNoReference(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approved(c)
	d := shotDoc(t)
	journey := d["journey"].([]any)
	last := journey[len(journey)-1].(map[string]any)
	d["journey"] = append(journey, map[string]any{"t": last["t"], "p": nil, "addon": "Memories", "k": "zzz", "Screenshot": "screenshots/WoWScrnShot_110126_999999.jpg"})
	e.ok(e.upload(c, d))
	e.fail(e.putShot(c, brumamar, "WoWScrnShot_110126_999999.jpg", readFile(t, filepath.Join(imagesDir, "small.jpg"))),
		http.StatusNotFound, "not_referenced")
}

func TestScreenshotBodyLimit(t *testing.T) {
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_SHOT_BYTES": strconv.Itoa(len(small))})
	c := newClient(1)
	e.approvedWithShots(c)
	if rec := e.putShot(c, brumamar, shotA, small); rec.Code != http.StatusCreated {
		t.Fatalf("a file at the limit: %d %s", rec.Code, rec.Body)
	}
	a := e.fail(e.putShot(c, brumamar, shotB, append(small, 0)), http.StatusRequestEntityTooLarge, "too_large")
	if a.Message == "" || e.storedShot(brumamar, shotB) != nil {
		t.Errorf("message %q, stored %v", a.Message, e.storedShot(brumamar, shotB) != nil)
	}
}

func TestScreenshotPixelLimit(t *testing.T) {
	small := readFile(t, filepath.Join(imagesDir, "small.jpg")) // 16 x 8
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_PIXELS": "127"})
	c := newClient(1)
	e.approvedWithShots(c)
	e.fail(e.putShot(c, brumamar, shotA, small), http.StatusRequestEntityTooLarge, "too_large")
	if e.storedShot(brumamar, shotA) != nil {
		t.Error("stored an image over the pixel limit")
	}
}

func TestScreenshotQuotaPerKey(t *testing.T) {
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	clean, err := images.Clean(small, ".jpg", 1000)
	if err != nil {
		t.Fatal(err)
	}
	one := int64(len(clean))

	// The limit holds one clean copy and a little more, so a second distinct file does not fit.
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_SHOT_BYTES_PER_KEY": strconv.FormatInt(one+one/2, 10)})
	c := newClient(1)
	e.approvedWithShots(c)
	if rec := e.putShot(c, brumamar, shotA, small); rec.Code != http.StatusCreated {
		t.Fatalf("first: %d %s", rec.Code, rec.Body)
	}
	e.fail(e.putShot(c, brumamar, shotB, small), http.StatusInsufficientStorage, "quota")
	if e.storedShot(brumamar, shotB) != nil {
		t.Error("the refused screenshot was stored")
	}
	if claim, _ := e.claim(brumamar); claim.ShotBytes != one {
		t.Errorf("shot_bytes = %d, want %d", claim.ShotBytes, one)
	}
	// A replace counts the size of the new file only, not both.
	if rec := e.putShot(c, brumamar, shotA, readFile(t, filepath.Join(imagesDir, "exif-gps.jpg"))); rec.Code != http.StatusCreated {
		t.Errorf("replace at the limit: %d %s", rec.Code, rec.Body)
	}

	// The limit is per key: another key stores its own.
	other := newClient(2)
	e.approved(other)
	d := shotDoc(t, shotA, shotB)
	d["character"].(map[string]any)["name"] = "Otro"
	d["character"].(map[string]any)["guid"] = "Player-1-0000ABCD"
	e.ok(e.upload(other, d))
	if rec := e.putShot(other, "wow/eu/brumamar/otro", shotA, small); rec.Code != http.StatusCreated {
		t.Errorf("other key: %d %s", rec.Code, rec.Body)
	}
}

func TestScreenshotQuotaCountsEveryCharacterOfTheKey(t *testing.T) {
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	clean, err := images.Clean(small, ".jpg", 1000)
	if err != nil {
		t.Fatal(err)
	}
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_SHOT_BYTES_PER_KEY": strconv.Itoa(len(clean) + len(clean)/2)})
	c := newClient(1)
	e.approved(c)
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	d := shotDoc(t, shotA, shotB)
	d["character"].(map[string]any)["name"] = "Otro"
	d["character"].(map[string]any)["guid"] = "Player-1-0000ABCD"
	e.ok(e.upload(c, d))
	if rec := e.putShot(c, brumamar, shotA, small); rec.Code != http.StatusCreated {
		t.Fatalf("first: %d %s", rec.Code, rec.Body)
	}
	e.fail(e.putShot(c, "wow/eu/brumamar/otro", shotA, small), http.StatusInsufficientStorage, "quota")
}

func TestDeleteRemovesScreenshotsAndTheirRows(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	e.putShot(c, brumamar, shotA, small)
	e.putShot(c, brumamar, shotB, small)
	claim, _ := e.claim(brumamar)

	if rec := e.do(c, "DELETE", "/api/v1/characters/"+brumamar, ""); rec.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", rec.Code, rec.Body)
	}
	if _, err := os.Stat(filepath.Join(e.data, "characters", itoa(claim.ID))); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("files stayed: %v", err)
	}
	if _, err := e.st.ShotOf(bg, claim.ID, shotA); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("shot rows stayed: %v", err)
	}
	e.fail(e.putShot(c, brumamar, shotA, small), http.StatusNotFound, "not_found")
}

func TestScreenshotsAndDeleteRaceLeaveNoOrphanFiles(t *testing.T) {
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	for i := 0; i < 5; i++ {
		e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CONCURRENT_UPLOADS": "4"})
		c := newClient(1)
		e.approvedWithShots(c)
		claim, _ := e.claim(brumamar)
		// The requests are signed here, because the test client is not safe for concurrent use.
		reqs := []*http.Request{
			e.request(c, "PUT", shotTarget(brumamar, shotA), string(small)),
			e.request(c, "PUT", shotTarget(brumamar, shotB), string(small)),
			e.request(c, "DELETE", "/api/v1/characters/"+brumamar, ""),
		}
		var wg sync.WaitGroup
		for _, req := range reqs {
			wg.Add(1)
			go func() {
				defer wg.Done()
				code := e.serve(req).Code
				ok := code == http.StatusCreated || code == http.StatusNotFound
				if req.Method == "DELETE" {
					ok = code == http.StatusNoContent
				}
				if !ok {
					t.Errorf("%s status %d", req.Method, code)
				}
			}()
		}
		wg.Wait()
		if _, err := os.Stat(filepath.Join(e.data, "characters", itoa(claim.ID))); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("round %d: a screenshot outlived the delete: %v", i, err)
		}
	}
}

func TestScreenshotWaitsForASlotThenAnswersBusy(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_CONCURRENT_UPLOADS": "1"})
	c := newClient(1)
	e.approvedWithShots(c)
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))

	e.api.slots <- struct{}{}
	e.api.uploadWait = 20 * time.Millisecond
	// A .tga name is refused before the wait for a slot.
	e.fail(e.putShot(c, brumamar, "WoWScrnShot_110126_114820.tga", readFile(t, filepath.Join(imagesDir, "small.tga"))),
		http.StatusUnsupportedMediaType, "unsupported_image")
	rec := e.putShot(c, brumamar, shotA, small)
	e.fail(rec, http.StatusServiceUnavailable, "busy")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("no Retry-After")
	}
	<-e.api.slots
	if rec := e.putShot(c, brumamar, shotA, small); rec.Code != http.StatusCreated {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	if len(e.api.slots) != 0 {
		t.Errorf("%d slots still taken", len(e.api.slots))
	}
}

func TestScreenshotDiskFailureStoresNothingAndKeepsNoRow(t *testing.T) {
	e := newEnv(t, openMode)
	fb := &failingBlobs{name: shotA}
	e.wrap = func(b store.Blobs) store.Blobs { fb.Blobs = b; return fb }
	e.start()
	c := newClient(1)
	e.approvedWithShots(c)
	small := readFile(t, filepath.Join(imagesDir, "small.jpg"))

	fb.fail = true
	a := e.fail(e.putShot(c, brumamar, shotA, small), http.StatusInternalServerError, "internal")
	if a.Message == "" || bytes.Contains(e.logs.Bytes(), small[:20]) {
		t.Errorf("message %q; logs %s", a.Message, e.logs)
	}
	claim, _ := e.claim(brumamar)
	if _, err := e.st.ShotOf(bg, claim.ID, shotA); !errors.Is(err, store.ErrNotFound) || claim.ShotBytes != 0 {
		t.Errorf("row after a failed write: %v, shot_bytes %d", err, claim.ShotBytes)
	}
	fb.fail = false
	if rec := e.putShot(c, brumamar, shotA, small); rec.Code != http.StatusCreated {
		t.Errorf("retry: %d %s", rec.Code, rec.Body)
	}
}

func TestScreenshotRowFailureRemovesTheNewFile(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	// A trigger that refuses the insert makes SetShot fail after the file is written.
	db, err := sql.Open("sqlite", "file:"+e.db+"?_pragma=busy_timeout(5000)")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec(`CREATE TRIGGER no_shots BEFORE INSERT ON shots BEGIN SELECT RAISE(ABORT, 'no'); END`); err != nil {
		t.Fatal(err)
	}
	e.fail(e.putShot(c, brumamar, shotA, readFile(t, filepath.Join(imagesDir, "small.jpg"))), http.StatusInternalServerError, "internal")
	if e.storedShot(brumamar, shotA) != nil {
		t.Error("a file without a row stayed on the disk")
	}
}

func TestScreenshotFailedReplaceKeepsNoFileOfTheNewUpload(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	first := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	if rec := e.putShot(c, brumamar, shotA, first); rec.Code != http.StatusCreated {
		t.Fatalf("first: %d %s", rec.Code, rec.Body)
	}
	want := e.storedShot(brumamar, shotA)
	db, err := sql.Open("sqlite", "file:"+e.db+"?_pragma=busy_timeout(5000)")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec(`CREATE TRIGGER no_shots BEFORE INSERT ON shots BEGIN SELECT RAISE(ABORT, 'no'); END`); err != nil {
		t.Fatal(err)
	}
	e.fail(e.putShot(c, brumamar, shotA, readFile(t, filepath.Join(imagesDir, "exif-gps.jpg"))), http.StatusInternalServerError, "internal")
	if e.storedShot(brumamar, shotA) != nil {
		t.Error("the file of the failed replace stayed under the row of the first upload")
	}
	if _, err := db.Exec(`DROP TRIGGER no_shots`); err != nil {
		t.Fatal(err)
	}
	if rec := e.putShot(c, brumamar, shotA, first); rec.Code != http.StatusCreated {
		t.Fatalf("retry of the first upload: %d %s", rec.Code, rec.Body)
	}
	if !bytes.Equal(e.storedShot(brumamar, shotA), want) {
		t.Error("the retry of the first upload did not store its clean copy")
	}
}

func TestScreenshotLogsNoBodyOrKey(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	e.putShot(c, brumamar, shotA, []byte("TOPSECRETBODY"))
	if bytes.Contains(e.logs.Bytes(), []byte("TOPSECRETBODY")) {
		t.Error("the log has the request body")
	}
}
