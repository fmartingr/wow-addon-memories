package validate

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestReadStoredReadsTheFilesTheServerWrote(t *testing.T) {
	for _, id := range []string{"eu-brumamar-nandu", "eu-los-errantes-nandu"} {
		dir := filepath.Join(expectedDir, id)
		read := func(name string) []byte {
			b, err := os.ReadFile(filepath.Join(dir, name))
			if err != nil {
				t.Fatal(err)
			}
			return b
		}
		up, err := ReadStored(read("character.json"), read("journey.jsonl"), read("trail.jsonl"), testNow)
		if err != nil {
			t.Fatalf("%s: %v", id, err)
		}
		journey, err := up.JourneyJSONL()
		if err != nil || !bytes.Equal(journey, read("journey.jsonl")) {
			t.Errorf("%s: the journey does not round trip: %v", id, err)
		}
		trail, err := up.TrailJSONL()
		if err != nil || !bytes.Equal(trail, read("trail.jsonl")) {
			t.Errorf("%s: the trail does not round trip: %v", id, err)
		}
	}
}

func TestReadStoredAcceptsEmptyListsAndRefusesDamage(t *testing.T) {
	character, err := os.ReadFile(filepath.Join(expectedDir, "eu-los-errantes-nandu", "character.json"))
	if err != nil {
		t.Fatal(err)
	}
	up, err := ReadStored(character, nil, nil, testNow)
	if err != nil || len(up.Records) != 0 || len(up.Chunks) != 0 {
		t.Fatalf("empty files: %+v, %v", up, err)
	}
	if _, err := ReadStored(character, []byte("{\"t\":1}\n"), nil, testNow); err == nil {
		t.Error("a record that fails the checks was accepted")
	}
	if _, err := ReadStored([]byte("{"), nil, nil, testNow); err == nil {
		t.Error("a damaged character.json was accepted")
	}
}

// A merge keeps the addons of every upload, so a stored character may hold more addons than one upload may send.
func TestReadStoredAcceptsMoreAddonsThanAnUpload(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join(expectedDir, "eu-los-errantes-nandu", "character.json"))
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	addons := map[string]any{}
	for i := range maxAddons + 1 {
		addons[fmt.Sprintf("Addon%d", i)] = map[string]any{"counts": map[string]any{}, "snap": map[string]any{}, "schema": 1, "writtenBy": "1.0"}
	}
	doc["addons"] = addons
	character, err := json.Marshal(doc)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ReadStored(character, nil, nil, testNow); err != nil {
		t.Errorf("a stored character with %d addons was refused: %v", maxAddons+1, err)
	}
}

// A merge of many uploads can pass the limits of one upload, and a lowered limit must not lock out stored data.
func TestStoredLimitsAreLooserThanAnUpload(t *testing.T) {
	lim := StoredLimits()
	if lim.MaxRecords <= 500_000 || lim.MaxDecodedBytes <= 64<<20 {
		t.Errorf("limits %+v are not looser than the upload defaults", lim)
	}
}

// A later catalog may change the fields of a kind; records stored under an older catalog must still load.
func TestReadStoredAcceptsFieldsThatTheCatalogDoesNotList(t *testing.T) {
	character, err := os.ReadFile(filepath.Join(expectedDir, "eu-los-errantes-nandu", "character.json"))
	if err != nil {
		t.Fatal(err)
	}
	journey := []byte(`{"addon":"Memories","file":"a.jpg","k":"ss","oldField":1,"p":null,"t":1793530000}` + "\n")
	up, err := ReadStored(character, journey, nil, testNow)
	if err != nil {
		t.Fatalf("a stored record with a field that the catalog no longer lists was refused: %v", err)
	}
	if up.Records[0]["oldField"] == nil {
		t.Error("the field was dropped")
	}
}
