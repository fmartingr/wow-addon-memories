package validate

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// The server accepts each character of testdata/expected and writes the same bytes back.
func TestExpectedCharactersPassAndRoundTrip(t *testing.T) {
	entries, err := os.ReadDir(expectedDir)
	if err != nil {
		t.Fatal(err)
	}
	checked := 0
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		checked++
		t.Run(e.Name(), func(t *testing.T) {
			assertRoundTrip(t, filepath.Join(expectedDir, e.Name()))
		})
	}
	if checked < 2 {
		t.Fatalf("found %d expected characters, want at least 2", checked)
	}
}

func assertRoundTrip(t *testing.T, dir string) *Upload {
	t.Helper()
	up, problems := readJSON(t, marshal(t, fixtureDoc(t, dir)), testLimits())
	if len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	for name, write := range map[string]func() ([]byte, error){
		"character.json": up.CharacterJSON,
		"journey.jsonl":  up.JourneyJSONL,
		"trail.jsonl":    up.TrailJSONL,
	} {
		want, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		got, err := write()
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, want) {
			t.Errorf("%s differs from the source:\n got %s\nwant %s", name, got, want)
		}
	}
	return up
}

func TestExpectedPaths(t *testing.T) {
	tests := map[string][4]string{
		"eu-brumamar-nandu":     {"wow", "eu", "brumamar", "nandu"},
		"eu-los-errantes-nandu": {"wow", "eu", "los-errantes", "nandu"},
	}
	for dir, want := range tests {
		up := assertRoundTrip(t, filepath.Join(expectedDir, dir))
		if got := [4]string{up.Flavor, up.Region, up.Realm, up.Name}; got != want {
			t.Errorf("%s: path = %v, want %v", dir, got, want)
		}
	}
}

// Real gathered data, when a copy is in dist-characters (it is not in the repository): every value that the
// gather writes must pass.
func TestRealGatherPasses(t *testing.T) {
	const root = "../../../dist-characters"
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Skip("no dist-characters folder")
	}
	for _, e := range entries {
		if e.IsDir() {
			t.Run(e.Name(), func(t *testing.T) {
				assertRoundTrip(t, filepath.Join(root, e.Name()))
			})
		}
	}
}
