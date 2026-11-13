package admin

import (
	"testing"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

func TestSettingsSaveAndShow(t *testing.T) {
	e := newEnv(t)
	br := e.browser()
	mustContain(t, br.get("/settings").Body.String(), "50.0%", `name="open" value="1" checked`)

	msg := br.act("/settings/save", form("max_data_mib", "32", "min_free_percent", "20"))
	mustContain(t, msg, "Open registration is off.")
	o, err := e.st.OpenSettings(bg)
	if err != nil || o != (store.OpenSettings{MaxDataBytes: 32 << 20, MinFreePercent: 20}) {
		t.Fatalf("settings = %+v, %v", o, err)
	}

	msg = br.act("/settings/save", form("open", "1", "max_data_mib", "32", "min_free_percent", "20"))
	mustContain(t, msg, "Open registration is on.")
	if o, _ := e.st.OpenSettings(bg); !o.Open {
		t.Error("the switch is off after it was turned on")
	}

	for _, bad := range [][]string{
		{"max_data_mib", "0", "min_free_percent", "20"},
		{"max_data_mib", "x", "min_free_percent", "20"},
		{"max_data_mib", "32", "min_free_percent", "100"},
		{"max_data_mib", "32", "min_free_percent", "-1"},
	} {
		mustContain(t, br.act("/settings/save", form(bad...)), "must be a whole number")
	}
}

func TestSettingsKeepOpenRegistrationOffOnALowDisk(t *testing.T) {
	e := newEnv(t)
	br := e.browser()
	e.freePercent = 8
	mustContain(t, br.get("/settings").Body.String(), "8.0%", "so open registration is off")
	if o, _ := e.st.OpenSettings(bg); o.Open {
		t.Error("the settings page did not close open registration on a low disk")
	}
	msg := br.act("/settings/save", form("open", "1", "max_data_mib", "32", "min_free_percent", "10"))
	mustContain(t, msg, "the settings stay as they were.")
	if o, _ := e.st.OpenSettings(bg); o.Open || o.MaxDataBytes == 32<<20 {
		t.Errorf("a refused save changed the settings: %+v", o)
	}
	mustContain(t, br.act("/settings/save", form("open", "1", "max_data_mib", "32", "min_free_percent", "5")), "Open registration is on.")
}

func TestKeysPageMarksOpenKeys(t *testing.T) {
	e := newEnv(t)
	c := newClient(1)
	if rec := e.register(c, ""); rec.Code != 201 {
		t.Fatalf("open registration: %d %s", rec.Code, rec.Body)
	}
	body := e.browser().get("/keys?q=open").Body.String()
	mustContain(t, body, c.fingerprint(), `<strong class="tag">open</strong>`, "not allowed", "1 result")
}

func TestKeyLimitsForm(t *testing.T) {
	e := newEnv(t)
	c, k := e.registered(1)
	br := e.browser()
	mustContain(t, br.get("/keys").Body.String(), "0 B of 512.0 MiB", "0 B of 5.0 GiB")

	mustContain(t, br.act("/keys/limits", form("key", id(k), "data_mib", "100", "shot_mib", "")), "The limits of key "+c.fingerprint()+" are saved.")
	if got := e.row(c); got.MaxDataBytes != 100<<20 || got.MaxShotBytes != 0 {
		t.Errorf("limits = %d and %d", got.MaxDataBytes, got.MaxShotBytes)
	}
	mustContain(t, br.get("/keys").Body.String(), "0 B of 100.0 MiB", `<strong class="tag">custom</strong>`, `name="data_mib" min="0" value="100"`)

	for _, bad := range []string{"-1", "x", "1.5"} {
		mustContain(t, br.act("/keys/limits", form("key", id(k), "data_mib", bad)), "must be a whole number of MiB")
	}
	br.act("/keys/limits", form("key", id(k), "data_mib", "0", "shot_mib", "0"))
	if got := e.row(c); got.MaxDataBytes != 0 || got.MaxShotBytes != 0 {
		t.Errorf("limits after a reset = %d and %d", got.MaxDataBytes, got.MaxShotBytes)
	}
}
