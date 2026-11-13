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
