package api

import (
	"encoding/json"
	"net/http"
	"path/filepath"
	"testing"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

func TestOpenKeyCannotUseScreenshots(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered2(c)
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))

	expectError(t, e.do(c, "POST", "/api/v1/screenshots/request", ""), http.StatusForbidden, "screenshots_unavailable")
	expectError(t, e.putShot(c, brumamar, shotA, []byte("x")), http.StatusForbidden, "screenshots_unavailable")

	var me struct {
		Open        bool   `json:"open"`
		Screenshots string `json:"screenshots"`
	}
	rec := e.do(c, "GET", "/api/v1/me", "")
	if err := json.Unmarshal(rec.Body.Bytes(), &me); err != nil || !me.Open || me.Screenshots != store.ShotsNone {
		t.Errorf("me = %d %s", rec.Code, rec.Body)
	}
}

func TestOpenKeyHasItsOwnDataLimit(t *testing.T) {
	e := newEnv(t, openMode)
	o := store.DefaultOpenSettings()
	o.Open, o.MaxDataBytes = true, 100
	if err := e.st.SetOpenSettings(bg, o); err != nil {
		t.Fatal(err)
	}
	e.refresh()
	open, invited := newClient(1), newClient(2)
	e.registered2(open)
	e.registered(invited)
	dir := filepath.Join(expectedDir, "eu-brumamar-nandu")
	e.fail(e.uploadDir(open, dir), http.StatusInsufficientStorage, "quota")
	e.ok(e.uploadDir(invited, dir))
}

func TestLowDiskClosesOpenRegistration(t *testing.T) {
	e := newEnv(t, openMode)
	before := newClient(1)
	e.registered2(before)

	e.freePercent = 5
	e.refresh()
	if rec := e.register(newClient(2), ""); rec.Code != http.StatusForbidden {
		t.Fatalf("open registration on a low disk = %d %s, want 403", rec.Code, rec.Body)
	}
	if o, _ := e.st.OpenSettings(bg); o.Open {
		t.Error("the low disk did not turn the switch off")
	}
	e.freePercent = 50
	e.refresh()
	if rec := e.register(newClient(3), ""); rec.Code != http.StatusForbidden {
		t.Errorf("open registration after the disk has space again = %d, want 403 until the admin turns it on", rec.Code)
	}

	// A key that registered before keeps working, and an invite still registers a new key.
	e.ok(e.uploadDir(before, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	if rec := e.register(before, ""); rec.Code != http.StatusOK {
		t.Errorf("registration of a known key = %d %s", rec.Code, rec.Body)
	}
	e.registered(newClient(4))
}

func (e *env) refresh() {
	e.t.Helper()
	if _, err := e.gate.Refresh(bg); err != nil {
		e.t.Fatal(err)
	}
}

func TestOpenKeyLimitIsTheSettingOnly(t *testing.T) {
	e := newEnv(t, map[string]string{"MEMORIES_REGISTRATION": "open", "MEMORIES_MAX_DATA_BYTES_PER_KEY": "100"})
	c := newClient(1)
	e.registered2(c)
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
}

func TestKeyLimitReplacesTheDefault(t *testing.T) {
	e := newEnv(t, openMode)
	open, invited := newClient(1), newClient(2)
	e.registered2(open)
	e.registered(invited)
	for c, dir := range map[*client]string{open: "eu-brumamar-nandu", invited: "eu-los-errantes-nandu"} {
		k, err := e.st.KeyByPublic(bg, c.public())
		if err != nil {
			t.Fatal(err)
		}
		if err := e.st.SetKeyLimits(bg, k.ID, 100, 0); err != nil {
			t.Fatal(err)
		}
		e.fail(e.uploadDir(c, filepath.Join(expectedDir, dir)), http.StatusInsufficientStorage, "quota")
		if err := e.st.SetKeyLimits(bg, k.ID, 1<<30, 0); err != nil {
			t.Fatal(err)
		}
		e.ok(e.uploadDir(c, filepath.Join(expectedDir, dir)))
	}
}

func TestKeyShotLimitReplacesTheDefault(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.approvedWithShots(c)
	k, err := e.st.KeyByPublic(bg, c.public())
	if err != nil {
		t.Fatal(err)
	}
	if err := e.st.SetKeyLimits(bg, k.ID, 0, 10); err != nil {
		t.Fatal(err)
	}
	src := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	e.fail(e.putShot(c, brumamar, shotA, src), http.StatusInsufficientStorage, "quota")
}

func TestApprovedOpenKeyUploadsScreenshots(t *testing.T) {
	e := newEnv(t, openMode)
	c := newClient(1)
	e.registered2(c)
	k, err := e.st.KeyByPublic(bg, c.public())
	if err != nil {
		t.Fatal(err)
	}
	if ok, err := e.st.ApproveScreenshots(bg, k.ID); !ok || err != nil {
		t.Fatalf("ApproveScreenshots of an open key = %v, %v", ok, err)
	}
	e.ok(e.uploadDir(c, filepath.Join(expectedDir, "eu-brumamar-nandu")))
	src := readFile(t, filepath.Join(imagesDir, "small.jpg"))
	if rec := e.putShot(c, brumamar, shotA, src); rec.Code != http.StatusCreated {
		t.Fatalf("screenshot of an approved open key: %d %s", rec.Code, rec.Body)
	}
	// The app still cannot ask: only the admin approves an open key.
	expectError(t, e.do(c, "POST", "/api/v1/screenshots/request", ""), http.StatusForbidden, "screenshots_unavailable")
}
