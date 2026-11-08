package validate

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

const expectedDir = "../../../testdata/expected"

var testNow = time.Unix(1794100000, 0)

func testLimits() Limits {
	return Limits{MaxDecodedBytes: 64 << 20, MaxText: 512, MaxRecords: 500_000, MaxChunks: 50_000, MaxPoints: 20_000}
}

func gzipBytes(t testing.TB, b []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(b); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func readJSON(t testing.TB, doc []byte, lim Limits) (*Upload, []Problem) {
	t.Helper()
	return Read(bytes.NewReader(gzipBytes(t, doc)), lim, testNow)
}

func decodeJSON(t testing.TB, b []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

func jsonLines(t testing.TB, b []byte) []any {
	t.Helper()
	out := []any{}
	for _, line := range bytes.Split(bytes.TrimSuffix(b, []byte("\n")), []byte("\n")) {
		if len(line) > 0 {
			out = append(out, decodeJSON(t, line))
		}
	}
	return out
}

// fixtureDoc builds the upload document of one folder with a journey, a trail and a character.json.
func fixtureDoc(t testing.TB, dir string) map[string]any {
	t.Helper()
	read := func(name string) []byte {
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	return map[string]any{
		"character": decodeJSON(t, read("character.json")),
		"journey":   jsonLines(t, read("journey.jsonl")),
		"trail":     jsonLines(t, read("trail.jsonl")),
	}
}

func marshal(t testing.TB, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// goodDoc is a character with 15 records and 1 trail chunk that passes every check.
func goodDoc(t testing.TB) map[string]any {
	t.Helper()
	return fixtureDoc(t, filepath.Join(expectedDir, "eu-brumamar-nandu"))
}

func character(d map[string]any) map[string]any { return d["character"].(map[string]any) }
func record(d map[string]any, i int) map[string]any {
	return d["journey"].([]any)[i].(map[string]any)
}
func chunk(d map[string]any, i int) map[string]any { return d["trail"].([]any)[i].(map[string]any) }
func num(s string) json.Number                     { return json.Number(s) }
