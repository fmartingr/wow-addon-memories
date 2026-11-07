package journal

import (
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"
)

var testKinds = ParseKinds(map[string]any{
	"ss":  "Memories;Screenshots;why,result,file",
	"lv":  "Memories;Progress;#level",
	"out": "Memories;Sessions;",
	"bad": "no separators",
	"num": 5,
})

func TestParseKinds(t *testing.T) {
	want := Kinds{
		"ss":  {Addon: "Memories", Group: "Screenshots", Fields: []Field{{"why", false}, {"result", false}, {"file", false}}},
		"lv":  {Addon: "Memories", Group: "Progress", Fields: []Field{{"level", true}}},
		"out": {Addon: "Memories", Group: "Sessions"},
	}
	if !reflect.DeepEqual(testKinds, want) {
		t.Fatalf("got %#v", testKinds)
	}
	if got := ParseKinds("not a table"); len(got) != 0 {
		t.Fatalf("got %v", got)
	}
}

func TestList(t *testing.T) {
	if got := List([]any{"a"}); !reflect.DeepEqual(got, []any{"a"}) {
		t.Errorf("list: %v", got)
	}
	got := List(map[string]any{"3": "c", "1": "a", "name": "x"})
	if !reflect.DeepEqual(got, []any{"a", "c"}) {
		t.Errorf("map: %v", got)
	}
	if got := List(nil); got != nil {
		t.Errorf("nil: %v", got)
	}
}

func TestLines(t *testing.T) {
	log := map[string]any{
		"chunks": []any{"1|||||in|login\n2|||||out", 7},
		"open":   []any{"3|||||pl|10", false},
	}
	want := []string{"1|||||in|login", "2|||||out", "3|||||pl|10"}
	if got := Lines(log); !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q", got)
	}
	if got := Lines(map[string]any{"chunks": map[string]any{}, "open": map[string]any{}}); got != nil {
		t.Fatalf("empty: %q", got)
	}
	if got := Lines("x"); got != nil {
		t.Fatalf("not a table: %q", got)
	}
}

func TestDecode(t *testing.T) {
	tests := []struct {
		name string
		line string
		want Record
	}{
		{"named fields", "1762437789|500|1429|4512|6120|ss|by hand|ok|WoWScrnShot_110626_140309.jpg", Record{
			"t": int64(1762437789), "p": int64(500), "m": int64(1429), "x": int64(4512), "y": int64(6120), "k": "ss",
			"why": "by hand", "result": "ok", "file": "WoWScrnShot_110626_140309.jpg",
		}},
		{"empty fixed and fields", "5|||||ss||failed", Record{
			"t": int64(5), "p": nil, "m": nil, "x": nil, "y": nil, "k": "ss", "result": "failed",
		}},
		{"numeric field", "5|||||lv|12", Record{"t": int64(5), "p": nil, "m": nil, "x": nil, "y": nil, "k": "lv", "level": int64(12)}},
		{"float field", "5|||||lv|1.5", Record{"t": int64(5), "p": nil, "m": nil, "x": nil, "y": nil, "k": "lv", "level": 1.5}},
		{"text in a numeric field", "5|||||lv|ten", Record{
			"t": int64(5), "p": nil, "m": nil, "x": nil, "y": nil, "k": "lv", "extra": map[string]any{"1": "ten"},
		}},
		{"values past the fields", "5|||||lv|3|x||y", Record{
			"t": int64(5), "p": nil, "m": nil, "x": nil, "y": nil, "k": "lv", "level": int64(3),
			"extra": map[string]any{"2": "x", "4": "y"},
		}},
		{"unknown kind", "5|1.5|x|||zz|a|b", Record{
			"t": int64(5), "p": 1.5, "m": "x", "x": nil, "y": nil, "k": "zz", "extra": map[string]any{"1": "a", "2": "b"},
		}},
		{"NaN is text", "5|||||lv|NaN", Record{
			"t": int64(5), "p": nil, "m": nil, "x": nil, "y": nil, "k": "lv", "extra": map[string]any{"1": "NaN"},
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := Decode(tt.line, testKinds)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("got %#v", got)
			}
		})
	}
}

func TestDecodeReservedNames(t *testing.T) {
	kinds := ParseKinds(map[string]any{"zz": "Sub;Test;t,session,name"})
	got, err := Decode("5|||||zz|9|s|n", kinds)
	if err != nil {
		t.Fatal(err)
	}
	want := Record{
		"t": int64(5), "p": nil, "m": nil, "x": nil, "y": nil, "k": "zz", "name": "n",
		"extra": map[string]any{"1": "9", "2": "s"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %#v", got)
	}
}

func TestDecodeErrors(t *testing.T) {
	if _, err := Decode("1|2|3|4|5", testKinds); !errors.Is(err, ErrShortLine) {
		t.Errorf("short: %v", err)
	}
	if _, err := Decode("x|2|3|4|5|in", testKinds); !errors.Is(err, ErrBadTime) {
		t.Errorf("time: %v", err)
	}
}

func TestNumber(t *testing.T) {
	for _, s := range []string{"0x10", "Inf", "1e999", "", "1_000", " 1"} {
		if v, ok := Number(s); ok {
			t.Errorf("%q gave %v", s, v)
		}
	}
	if v, ok := Number("-2e3"); !ok || v != -2000.0 {
		t.Errorf("-2e3 gave %v", v)
	}
	if v, ok := Number("99999999999999999999"); !ok || v != 1e20 {
		t.Errorf("a large number gave %v", v)
	}
}

func TestInt(t *testing.T) {
	for _, v := range []any{int64(3), 3.0, json.Number("3")} {
		if n, ok := Int(v); !ok || n != 3 {
			t.Errorf("%#v gave %d %v", v, n, ok)
		}
	}
	for _, v := range []any{3.5, json.Number("3.5"), "3", nil} {
		if _, ok := Int(v); ok {
			t.Errorf("%#v gave a number", v)
		}
	}
}

func TestRecordHelpers(t *testing.T) {
	r := Record{"t": json.Number("12"), "file": "a", "n": 1}
	if r.T() != 12 || r.String("file") != "a" || r.String("n") != "" || r.String("none") != "" {
		t.Fatalf("helpers: %d %q", r.T(), r.String("file"))
	}
}

func TestDecodeChunk(t *testing.T) {
	c, err := DecodeChunk(map[string]any{
		"s": int64(100), "t": int64(1000), "m": int64(1429), "n": int64(3), "d": "0,4512,6120,m;2,4530,6101;4,4560,6080,mc",
	})
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(c)
	want := `{"s":100,"t":1000,"m":1429,"n":3,"pts":[[1000,4512,6120,"m"],[1002,4530,6101,"m"],[1004,4560,6080,"mc"]]}`
	if string(b) != want {
		t.Fatalf("got %s", b)
	}
	var back Chunk
	if err := json.Unmarshal(b, &back); err != nil || !reflect.DeepEqual(back, c) {
		t.Fatalf("round trip: %v %#v", err, back)
	}
}

func TestDecodeChunkEdges(t *testing.T) {
	c, err := DecodeChunk(map[string]any{"t": int64(1), "m": int64(2), "d": ""})
	if err != nil || c.S != nil || c.N != 0 || len(c.Pts) != 0 {
		t.Fatalf("empty: %v %#v", err, c)
	}
	c, err = DecodeChunk(map[string]any{"t": int64(1), "m": int64(2), "d": "0,1,2"})
	if err != nil || c.Pts[0].Flags != "-" {
		t.Fatalf("no flags: %v %#v", err, c)
	}
	bad := []any{
		"x",
		map[string]any{"m": int64(2), "d": ""},
		map[string]any{"t": int64(1), "m": int64(2), "d": "0,1"},
		map[string]any{"t": int64(1), "m": int64(2), "d": "99999999999999999999,1,2"},
	}
	for _, v := range bad {
		if _, err := DecodeChunk(v); !errors.Is(err, ErrBadChunk) {
			t.Errorf("%v: %v", v, err)
		}
	}
}

func TestTrail(t *testing.T) {
	chunks, bad := Trail(map[string]any{
		"v":      int64(1),
		"chunks": []any{map[string]any{"t": int64(1), "m": int64(2), "d": "0,1,2"}, "broken"},
		"open":   map[string]any{"t": int64(5), "m": int64(2), "d": "0,3,4,m", "o": int64(1)},
	})
	if bad != 1 || len(chunks) != 2 || chunks[1].T != 5 {
		t.Fatalf("got %d %#v", bad, chunks)
	}
	if chunks, bad := Trail(nil); chunks != nil || bad != 0 {
		t.Fatalf("nil: %v %d", chunks, bad)
	}
}

func TestPointUnmarshalErrors(t *testing.T) {
	var p Point
	for _, s := range []string{`{}`, `[1,2,3]`, `["a",2,3,"-"]`} {
		if err := json.Unmarshal([]byte(s), &p); err == nil {
			t.Errorf("%s: no error", s)
		}
	}
	if err := json.Unmarshal([]byte(`[1,2,3,"m"]`), &p); err != nil || !strings.EqualFold(p.Flags, "m") {
		t.Errorf("good point: %v", err)
	}
}
