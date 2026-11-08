package validate

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func fuzzLimits() Limits {
	return Limits{MaxDecodedBytes: 1 << 20, MaxText: 512, MaxRecords: 1000, MaxChunks: 100, MaxPoints: 1000}
}

// storedDoc turns the stored files of an accepted upload back into an upload document.
func storedDoc(t *testing.T, up *Upload) []byte {
	t.Helper()
	character, err := up.CharacterJSON()
	if err != nil {
		t.Fatal(err)
	}
	journey, err := up.JourneyJSONL()
	if err != nil {
		t.Fatal(err)
	}
	trail, err := up.TrailJSONL()
	if err != nil {
		t.Fatal(err)
	}
	list := func(lines []byte) []byte {
		out := []byte("[")
		for i, l := range bytes.Split(bytes.TrimSuffix(lines, []byte("\n")), []byte("\n")) {
			if len(l) == 0 {
				continue
			}
			if i > 0 {
				out = append(out, ',')
			}
			out = append(out, l...)
		}
		return append(out, ']')
	}
	return []byte(`{"character":` + string(character) + `,"journey":` + string(list(journey)) + `,"trail":` + string(list(trail)) + `}`)
}

func FuzzUpload(f *testing.F) {
	entries, err := os.ReadDir(expectedDir)
	if err != nil {
		f.Fatal(err)
	}
	for _, e := range entries {
		if e.IsDir() {
			f.Add(marshal(f, fixtureDoc(f, filepath.Join(expectedDir, e.Name()))))
		}
	}
	f.Add([]byte(`{"character":{},"journey":[],"trail":[]}`))
	f.Add([]byte(`{"journey":[{"t":1,"t":2}]}`))
	f.Add([]byte(`[[[[[[[[[[[[[[[[[[[[[[[[[[[[[`))
	f.Add([]byte("\xef\xbb\xbf{}"))
	f.Fuzz(func(t *testing.T, doc []byte) {
		for _, body := range [][]byte{gzipBytes(t, doc), doc} {
			up, problems := Read(bytes.NewReader(body), fuzzLimits(), testNow)
			if (up == nil) == (len(problems) == 0) {
				t.Fatalf("up is nil: %v, problems: %d; want exactly one of them", up == nil, len(problems))
			}
			if len(problems) > MaxProblems {
				t.Fatalf("%d problems", len(problems))
			}
			if up == nil {
				continue
			}
			again, problems := Read(bytes.NewReader(gzipBytes(t, storedDoc(t, up))), fuzzLimits(), testNow)
			if again == nil {
				t.Fatalf("the stored files do not pass again: %+v", problems)
			}
			a, _ := up.CharacterJSON()
			b, _ := again.CharacterJSON()
			if !bytes.Equal(a, b) {
				t.Fatalf("the stored character changes on a second pass:\n%s\n%s", a, b)
			}
		}
	})
}
