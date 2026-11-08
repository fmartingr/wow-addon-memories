package jsonw

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func goEncode(t *testing.T, v any, indent string) []byte {
	t.Helper()
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", indent)
	if err := enc.Encode(v); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestStringsMatchGoWithHTMLEscapingOff(t *testing.T) {
	for _, s := range []string{
		"", "plain", "Ñandú", `quote " and \ backslash`, "<b>&amp;</b>", "tab\tnew\nline\rret\bback\fform",
		"\x00\x01\x1f\x7f", "line\u2028sep\u2029para", "emoji 😀", "bad \xff\xfe bytes", "\ufffd", "日本語",
	} {
		got, err := Marshal(s, false)
		if err != nil {
			t.Fatal(err)
		}
		if want := goEncode(t, s, ""); !bytes.Equal(got, want) {
			t.Errorf("Marshal(%q) = %s, want %s", s, got, want)
		}
	}
}

func TestHTMLCharactersStayAsTheyAre(t *testing.T) {
	got, err := Marshal("<a href='x'>&</a>", false)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "\"<a href='x'>&</a>\"\n" {
		t.Errorf("got %s", got)
	}
}

func TestMapsMatchGoWithAndWithoutIndent(t *testing.T) {
	doc := map[string]any{
		"b": []any{json.Number("1"), json.Number("2.50"), "x", nil, true, false, []any{}, map[string]any{}},
		"a": map[string]any{"z": json.Number("-0.5"), "é": "e", "Z": "upper", "ÿ": "y", "\U0001F600": "smile", "\uffee": "bmp"},
		"c": []any{map[string]any{"k": []any{json.Number("1e3")}}},
		"d": "",
	}
	for _, indent := range []string{"", " "} {
		got, err := Marshal(doc, indent != "")
		if err != nil {
			t.Fatal(err)
		}
		if want := goEncode(t, doc, indent); !bytes.Equal(got, want) {
			t.Errorf("indent %q:\n got %s\nwant %s", indent, got, want)
		}
	}
}

func TestKeysSortByUTF8Bytes(t *testing.T) {
	got, err := Marshal(map[string]any{"\uffee": 1, "\U0001F600": 2, "b": 3}, false)
	if err != nil {
		t.Fatal(err)
	}
	if want := "{\"b\":3,\"\uffee\":1,\"\U0001F600\":2}\n"; string(got) != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

type pair struct{ a, b int64 }

func (p pair) JSONValue() any { return []any{p.a, p.b} }

type pairs []pair

func (p pairs) Len() int     { return len(p) }
func (p pairs) At(i int) any { return p[i] }

func TestOrderedValuerAndArray(t *testing.T) {
	v := Ordered{{"z", int64(1)}, {"a", pairs{{1, 2}, {3, 4}}}, {"m", pair{5, 6}}, {"n", nil}, {"i", 7}, {"e", pairs{}}}
	got, err := Marshal(v, false)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"z":1,"a":[[1,2],[3,4]],"m":[5,6],"n":null,"i":7,"e":[]}` + "\n"
	if string(got) != want {
		t.Errorf("got %s, want %s", got, want)
	}
	got, err = Marshal(v, true)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "\n \"a\": [\n  [\n   1,\n   2\n  ],") {
		t.Errorf("indent is wrong:\n%s", got)
	}
}

func TestEmptyNumberIsZero(t *testing.T) {
	got, err := Marshal(json.Number(""), false)
	if err != nil || string(got) != "0\n" {
		t.Errorf("got %q, %v", got, err)
	}
}

func TestUnsupportedTypeIsAnError(t *testing.T) {
	for _, v := range []any{1.5, struct{}{}, []string{"a"}, Ordered{{"k", 2.5}}, []any{make(chan int)}} {
		if _, err := Marshal(v, false); err == nil {
			t.Errorf("Marshal(%T) gave no error", v)
		}
	}
	if _, err := Lines(1, func(int) any { return 1.5 }); err == nil {
		t.Error("Lines gave no error for a float")
	}
}

func TestLines(t *testing.T) {
	got, err := Lines(3, func(i int) any { return map[string]any{"i": i, "a": "x"} })
	if err != nil {
		t.Fatal(err)
	}
	if want := "{\"a\":\"x\",\"i\":0}\n{\"a\":\"x\",\"i\":1}\n{\"a\":\"x\",\"i\":2}\n"; string(got) != want {
		t.Errorf("got %q", got)
	}
	if got, err := Lines(0, nil); err != nil || len(got) != 0 {
		t.Errorf("Lines(0) = %q, %v", got, err)
	}
}

func decode(t *testing.T, b []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

// orderAddons gives each addon entry the key order of the gather, which a map cannot keep.
func orderAddons(t *testing.T, doc any) {
	t.Helper()
	addons, _ := doc.(map[string]any)["addons"].(map[string]any)
	for name, e := range addons {
		m := e.(map[string]any)
		addons[name] = Ordered{{"counts", m["counts"]}, {"snap", m["snap"]}, {"schema", m["schema"]}, {"writtenBy", m["writtenBy"]}}
	}
}

func TestExpectedFilesRoundTripByteForByte(t *testing.T) {
	const root = "../../../testdata/expected"
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(root, e.Name())
		t.Run(e.Name(), func(t *testing.T) {
			src, err := os.ReadFile(filepath.Join(dir, "character.json"))
			if err != nil {
				t.Fatal(err)
			}
			doc := decode(t, src)
			orderAddons(t, doc)
			got, err := Marshal(doc, true)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(got, src) {
				t.Errorf("character.json differs:\n got %s\nwant %s", got, src)
			}

			src, err = os.ReadFile(filepath.Join(dir, "journey.jsonl"))
			if err != nil {
				t.Fatal(err)
			}
			lines := bytes.SplitAfter(src, []byte("\n"))
			lines = lines[:len(lines)-1]
			got, err = Lines(len(lines), func(i int) any {
				rec := decode(t, lines[i]).(map[string]any)
				if notes, ok := rec["notes"].([]any); ok {
					for j, n := range notes {
						m := n.(map[string]any)
						notes[j] = Ordered{{"source", m["source"]}, {"note", m["note"]}}
					}
				}
				return rec
			})
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(got, src) {
				t.Errorf("journey.jsonl differs:\n got %s\nwant %s", got, src)
			}

			src, err = os.ReadFile(filepath.Join(dir, "trail.jsonl"))
			if err != nil {
				t.Fatal(err)
			}
			lines = bytes.SplitAfter(src, []byte("\n"))
			lines = lines[:len(lines)-1]
			got, err = Lines(len(lines), func(i int) any {
				m := decode(t, lines[i]).(map[string]any)
				return Ordered{{"s", m["s"]}, {"t", m["t"]}, {"m", m["m"]}, {"n", m["n"]}, {"pts", m["pts"]}}
			})
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(got, src) {
				t.Errorf("trail.jsonl differs:\n got %s\nwant %s", got, src)
			}
		})
	}
}
