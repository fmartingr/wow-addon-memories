package validate

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"unicode/utf8"
)

type mutation struct {
	name   string
	mutate func(d map[string]any)
	file   string
	line   int
	field  string
	reason string // part of the reason; empty when the upload must pass
}

func runMutations(t *testing.T, tests []mutation) {
	t.Helper()
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			d := goodDoc(t)
			tc.mutate(d)
			up, problems := readJSON(t, marshal(t, d), testLimits())
			if tc.reason == "" {
				if len(problems) > 0 || up == nil {
					t.Fatalf("want a pass, got %+v", problems)
				}
				return
			}
			if up != nil {
				t.Fatal("got an upload and problems, want only problems")
			}
			for _, p := range problems {
				if p.File == tc.file && p.Line == tc.line && p.Field == tc.field && strings.Contains(p.Reason, tc.reason) {
					return
				}
			}
			t.Fatalf("want file %q line %d field %q reason containing %q, got %+v", tc.file, tc.line, tc.field, tc.reason, problems)
		})
	}
}

func set(m map[string]any, key string, v any) { m[key] = v }

func TestCharacterRules(t *testing.T) {
	c := func(d map[string]any) map[string]any { return character(d) }
	bad := func(name, field, reason string, mutate func(c map[string]any)) mutation {
		return mutation{name, func(d map[string]any) { mutate(c(d)) }, "character", 0, field, reason}
	}
	good := func(name string, mutate func(c map[string]any)) mutation {
		return mutation{name: name, mutate: func(d map[string]any) { mutate(c(d)) }}
	}
	runMutations(t, []mutation{
		bad("guid wrong form", "guid", "GUID", func(c map[string]any) { c["guid"] = "Player-1-abcdef01" }),
		bad("guid not text", "guid", "GUID", func(c map[string]any) { c["guid"] = num("5") }),
		bad("guid missing", "guid", "missing", func(c map[string]any) { delete(c, "guid") }),
		bad("name empty", "name", "empty", func(c map[string]any) { c["name"] = "" }),
		bad("name too long", "name", "at most 48", func(c map[string]any) { c["name"] = strings.Repeat("a", 49) }),
		good("name of 48 bytes", func(c map[string]any) { c["name"] = strings.Repeat("a", 48) }),
		bad("name with a pipe", "name", "|", func(c map[string]any) { c["name"] = "a|b" }),
		bad("name with a control character", "name", "control", func(c map[string]any) { c["name"] = "a\x00b" }),
		bad("name with DEL", "name", "control", func(c map[string]any) { c["name"] = "a\x7fb" }),
		bad("name with a newline", "name", "control", func(c map[string]any) { c["name"] = "a\nb" }),
		bad("name is a number", "name", "text", func(c map[string]any) { c["name"] = num("1") }),
		bad("region lower case", "region", "two upper-case", func(c map[string]any) { c["region"] = "eu" }),
		bad("region of 3 letters", "region", "two upper-case", func(c map[string]any) { c["region"] = "EUR" }),
		bad("flavor upper case", "flavor", "lower case", func(c map[string]any) { c["flavor"] = "Retail" }),
		bad("flavor with a dash", "flavor", "lower case", func(c map[string]any) { c["flavor"] = "a-b" }),
		bad("flavor too long", "flavor", "lower case", func(c map[string]any) { c["flavor"] = strings.Repeat("a", 33) }),
		good("flavor with an underscore", func(c map[string]any) { c["flavor"] = "classic_era" }),
		bad("realm empty", "realm", "empty", func(c map[string]any) { c["realm"] = "" }),
		bad("realm too long", "realm", "at most 64", func(c map[string]any) { c["realm"] = strings.Repeat("r", 65) }),
		good("realm with a dash and a space", func(c map[string]any) { c["realm"] = "Aa-Bb Cc"; c["realmLabel"] = "Aa-Bb Cc" }),
		bad("realmLabel empty", "realmLabel", "empty", func(c map[string]any) { c["realmLabel"] = "" }),
		bad("level is a float", "level", "whole number", func(c map[string]any) { c["level"] = num("10.0") }),
		bad("level zero", "level", "1 to 100", func(c map[string]any) { c["level"] = num("0") }),
		bad("level 101", "level", "1 to 100", func(c map[string]any) { c["level"] = num("101") }),
		good("level 100", func(c map[string]any) { c["level"] = num("100") }),
		bad("level is text", "level", "whole number", func(c map[string]any) { c["level"] = "10" }),
		bad("class is a number", "class", "text", func(c map[string]any) { c["class"] = num("1") }),
		bad("race empty", "race", "empty", func(c map[string]any) { c["race"] = "" }),
		bad("faction missing", "faction", "missing", func(c map[string]any) { delete(c, "faction") }),
		bad("sex 4", "sex", "0 to 3", func(c map[string]any) { c["sex"] = num("4") }),
		good("sex 0", func(c map[string]any) { c["sex"] = num("0") }),
		bad("first is a list", "first", "object", func(c map[string]any) { c["first"] = []any{} }),
		bad("first with an unknown key", "first.zz", "first record", func(c map[string]any) { c["first"] = map[string]any{"zz": num("1")} }),
		bad("first value is text", "first.t", "finite number", func(c map[string]any) { c["first"] = map[string]any{"t": "x"} }),
		good("first with null values", func(c map[string]any) { c["first"] = map[string]any{"t": nil, "x": nil} }),
		good("first with wait", func(c map[string]any) { c["first"] = map[string]any{"level": num("1"), "wait": true} }),
		good("first absent", func(c map[string]any) { delete(c, "first") }),
		bad("first wait is a number", "first.wait", "true, false or null", func(c map[string]any) { c["first"] = map[string]any{"wait": num("1")} }),
		bad("flags is a list", "flags", "object", func(c map[string]any) { c["flags"] = []any{} }),
		bad("flag is a number", "flags.hardcore", "true or false", func(c map[string]any) { c["flags"] = map[string]any{"hardcore": num("1")} }),
		bad("flag with a bad name", "flags.bad name", "flag name", func(c map[string]any) { c["flags"] = map[string]any{"bad name": true} }),
		bad("too many flags", "flags", "at most 64", func(c map[string]any) {
			f := map[string]any{}
			for i := range 65 {
				f[fmt.Sprintf("f%d", i)] = true
			}
			c["flags"] = f
		}),
		bad("sessions is an object", "sessions", "list", func(c map[string]any) { c["sessions"] = map[string]any{} }),
		bad("session is a number", "sessions[0]", "object", func(c map[string]any) { c["sessions"] = []any{num("1")} }),
		bad("session without start", "sessions[0].start", "missing", func(c map[string]any) { c["sessions"] = []any{map[string]any{}} }),
		bad("session start is a float", "sessions[0].start", "whole number", func(c map[string]any) { c["sessions"] = []any{map[string]any{"start": num("1.5")}} }),
		bad("session with an unknown key", "sessions[0].zz", "session", func(c map[string]any) {
			c["sessions"] = []any{map[string]any{"start": num("1"), "zz": num("1")}}
		}),
		bad("session how is a number", "sessions[0].how", "text", func(c map[string]any) {
			c["sessions"] = []any{map[string]any{"start": num("1"), "how": num("1")}}
		}),
		bad("session tz is text", "sessions[0].tz", "whole number", func(c map[string]any) {
			c["sessions"] = []any{map[string]any{"start": num("1"), "tz": "x"}}
		}),
		good("session with null tz and played0 of -1", func(c map[string]any) {
			c["sessions"] = []any{map[string]any{"start": num("1"), "tz": nil, "played0": num("-1"), "played1": num("5"), "last": num("9"), "computer": "a", "how": "login"}}
		}),
		good("no sessions", func(c map[string]any) { c["sessions"] = []any{} }),
		bad("addons is a list", "addons", "object", func(c map[string]any) { c["addons"] = []any{} }),
		bad("addon name with a space", "addons.bad name", "addon name", func(c map[string]any) { c["addons"] = map[string]any{"bad name": map[string]any{}} }),
		bad("addon entry is text", "addons.Memories", "object", func(c map[string]any) { c["addons"] = map[string]any{"Memories": "x"} }),
		bad("addon entry with an unknown key", "addons.Memories.zz", "addon entry", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["zz"] = num("1")
		}),
		bad("addon entry without schema", "addons.Memories.schema", "missing", func(c map[string]any) {
			delete(c["addons"].(map[string]any)["Memories"].(map[string]any), "schema")
		}),
		bad("addon schema is a float", "addons.Memories.schema", "whole number", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["schema"] = num("1.5")
		}),
		bad("addon writtenBy is a number", "addons.Memories.writtenBy", "text", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["writtenBy"] = num("1")
		}),
		bad("addon counts is a list", "addons.Memories.counts", "object", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = []any{}
		}),
		bad("counts value is a boolean", "addons.Memories.counts.a", "number, text", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{"a": true}
		}),
		bad("counts value is a list", "addons.Memories.counts.a", "number, text", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{"a": []any{}}
		}),
		bad("counts nested too deep", "addons.Memories.counts.a.b.c.d", "levels deep", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{"a": map[string]any{"b": map[string]any{"c": map[string]any{"d": map[string]any{"e": num("1")}}}}}
		}),
		good("counts nested 4 levels", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{"a": map[string]any{"b": map[string]any{"c": num("1")}}}
		}),
		bad("counts key too long", "addons.Memories.counts."+strings.Repeat("k", 129), "key", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{strings.Repeat("k", 129): num("1")}
		}),
		bad("counts key __proto__", "addons.Memories.counts.__proto__", "key", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{"__proto__": num("1")}
		}),
		bad("counts key empty", "addons.Memories.counts.", "key", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{"": num("1")}
		}),
		good("counts with a pipe in the key and null in snap", func(c map[string]any) {
			e := c["addons"].(map[string]any)["Memories"].(map[string]any)
			e["counts"] = map[string]any{"made|Venda de lino|First Aid": num("1")}
			e["snap"] = map[string]any{"a": nil, "skills": "a;b|c"}
		}),
		bad("snap text too long", "addons.Memories.snap.skills", "at most 4096", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["snap"] = map[string]any{"skills": strings.Repeat("s", 4097)}
		}),
		bad("snap text with a control character", "addons.Memories.snap.skills", "control", func(c map[string]any) {
			c["addons"].(map[string]any)["Memories"].(map[string]any)["snap"] = map[string]any{"skills": "a\tb"}
		}),
		bad("too many addons", "addons", "at most 32", func(c map[string]any) {
			a := map[string]any{}
			for i := range 33 {
				a[fmt.Sprintf("A%d", i)] = map[string]any{}
			}
			c["addons"] = a
		}),
		bad("too many values in counts", "addons.Memories.counts", "20000 values", func(c map[string]any) {
			counts := map[string]any{}
			for i := range 20_001 {
				counts[fmt.Sprintf("k%d", i)] = num("1")
			}
			c["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = counts
		}),
		good("extra key surname", func(c map[string]any) { c["surname"] = "Brumamar" }),
		good("extra key with a number, true and null", func(c map[string]any) { c["a"] = num("1"); c["b"] = true; c["c"] = nil }),
		bad("extra key in upper case", "Surname", "allowed key", func(c map[string]any) { c["Surname"] = "x" }),
		bad("extra key __proto__", "__proto__", "allowed key", func(c map[string]any) { c["__proto__"] = "x" }),
		bad("extra key with a list", "surname", "text, a number", func(c map[string]any) { c["surname"] = []any{} }),
		bad("extra key text with a pipe", "surname", "|", func(c map[string]any) { c["surname"] = "a|b" }),
		bad("too many keys", "", "at most 64", func(c map[string]any) {
			for i := range 60 {
				c[fmt.Sprintf("k%d", i)] = "x"
			}
		}),
		{"character is a list", func(d map[string]any) { d["character"] = []any{} }, "character", 0, "", "object"},
	})
}

func TestRecordRules(t *testing.T) {
	bad := func(name string, line int, field, reason string, mutate func(r map[string]any)) mutation {
		return mutation{name, func(d map[string]any) { mutate(record(d, line-1)) }, "journey", line, field, reason}
	}
	good := func(name string, mutate func(r map[string]any)) mutation {
		return mutation{name: name, mutate: func(d map[string]any) { mutate(record(d, 3)) }}
	}
	runMutations(t, []mutation{
		bad("t is a float", 4, "t", "whole number", func(r map[string]any) { r["t"] = num("1793530060.5") }),
		bad("t before 2005", 4, "t", "whole number", func(r map[string]any) { r["t"] = num("1104537599") }),
		bad("t in the far future", 4, "t", "whole number", func(r map[string]any) { r["t"] = num("1794186401") }),
		{"t a day after now", func(d map[string]any) { record(d, 14)["t"] = num("1794186400") }, "", 0, "", ""},
		bad("t is text", 4, "t", "whole number", func(r map[string]any) { r["t"] = "x" }),
		bad("t earlier than the record before", 4, "t", "time order", func(r map[string]any) { r["t"] = num("1793530001") }),
		bad("t missing", 4, "t", "missing", func(r map[string]any) { delete(r, "t") }),
		good("p null", func(r map[string]any) { r["p"] = nil }),
		bad("p negative", 4, "p", "0 to", func(r map[string]any) { r["p"] = num("-1") }),
		bad("p too large", 4, "p", "0 to", func(r map[string]any) { r["p"] = num("10000000001") }),
		bad("p missing", 4, "p", "missing", func(r map[string]any) { delete(r, "p") }),
		good("m absent", func(r map[string]any) { delete(r, "m") }),
		good("m null", func(r map[string]any) { r["m"] = nil }),
		bad("m too large", 4, "m", "0 to 100000", func(r map[string]any) { r["m"] = num("100001") }),
		bad("m is a float", 4, "m", "whole number", func(r map[string]any) { r["m"] = num("1.5") }),
		good("x with a fraction", func(r map[string]any) { r["x"] = num("4512.5") }),
		bad("x above 10000", 4, "x", "0 to 10000", func(r map[string]any) { r["x"] = num("10000.5") }),
		bad("y negative", 4, "y", "0 to 10000", func(r map[string]any) { r["y"] = num("-0.5") }),
		bad("y is text", 4, "y", "finite number", func(r map[string]any) { r["y"] = "5" }),
		bad("y is infinite", 4, "y", "finite number", func(r map[string]any) { r["y"] = num("1e999") }),
		bad("y has a huge number of digits", 4, "y", "finite number", func(r map[string]any) { r["y"] = num("0." + strings.Repeat("1", 40)) }),
		bad("k is a number", 4, "k", "text", func(r map[string]any) { r["k"] = num("1") }),
		bad("k missing", 4, "k", "missing", func(r map[string]any) { delete(r, "k") }),
		bad("new kind in upper case", 4, "k", "valid new kind name", func(r map[string]any) { r["k"] = "ZZ" }),
		bad("new kind too long", 4, "k", "valid new kind name", func(r map[string]any) { r["k"] = "abcdefghi" }),
		bad("addon with a space", 4, "addon", "addon", func(r map[string]any) { r["addon"] = "A B" }),
		bad("addon missing", 4, "addon", "missing", func(r map[string]any) { delete(r, "addon") }),
		good("session null", func(r map[string]any) { r["session"] = nil }),
		good("session absent", func(r map[string]any) { delete(r, "session") }),
		bad("session zero", 4, "session", "1 to", func(r map[string]any) { r["session"] = num("0") }),
		bad("session is text", 4, "session", "whole number", func(r map[string]any) { r["session"] = "1" }),
		bad("extra is a list", 4, "extra", "object", func(r map[string]any) { r["extra"] = []any{} }),
		bad("extra key 0", 4, "extra.0", "field number", func(r map[string]any) { r["extra"] = map[string]any{"0": "a"} }),
		bad("extra key with 4 digits", 4, "extra.1000", "field number", func(r map[string]any) { r["extra"] = map[string]any{"1000": "a"} }),
		bad("extra value is a number", 4, "extra.1", "text", func(r map[string]any) { r["extra"] = map[string]any{"1": num("5")} }),
		good("extra with 999", func(r map[string]any) { r["extra"] = map[string]any{"999": "a", "1": "b"} }),
		bad("notes is an object", 5, "notes", "list", func(r map[string]any) { r["notes"] = map[string]any{} }),
		bad("note is text", 5, "notes[0]", "object", func(r map[string]any) { r["notes"] = []any{"x"} }),
		bad("note without source", 5, "notes[0].source", "missing", func(r map[string]any) { r["notes"] = []any{map[string]any{"note": "a"}} }),
		bad("note with another key", 5, "notes[0].zz", "note", func(r map[string]any) {
			r["notes"] = []any{map[string]any{"source": "a", "note": "b", "zz": "c"}}
		}),
		bad("note is a number", 5, "notes[0].note", "text", func(r map[string]any) { r["notes"] = []any{map[string]any{"source": "a", "note": num("1")}} }),
		bad("17 notes", 5, "notes", "at most 16", func(r map[string]any) {
			n := make([]any, 17)
			for i := range n {
				n[i] = map[string]any{"source": "a", "note": "b"}
			}
			r["notes"] = n
		}),
		bad("screenshot in another folder", 5, "screenshot", "screenshot path", func(r map[string]any) { r["screenshot"] = "../x/WoWScrnShot_110126_114820.jpg" }),
		bad("screenshot with a bad extension", 5, "screenshot", "screenshot path", func(r map[string]any) { r["screenshot"] = "screenshots/WoWScrnShot_110126_114820.gif" }),
		bad("screenshot is null", 5, "screenshot", "screenshot path", func(r map[string]any) { r["screenshot"] = nil }),
		bad("screenshot with a short stamp", 5, "screenshot", "screenshot path", func(r map[string]any) { r["screenshot"] = "screenshots/WoWScrnShot_1_2.png" }),
		{"screenshot png and tga pass", func(d map[string]any) {
			record(d, 4)["screenshot"] = "screenshots/WoWScrnShot_110126_114820.png"
			record(d, 9)["screenshot"] = "screenshots/WoWScrnShot_110126_115001.tga"
		}, "", 0, "", ""},
		bad("known kind with a field of another kind", 4, "level", "field of this kind", func(r map[string]any) { r["level"] = num("5") }),
		bad("known text field with a number", 4, "zone", "Must be text", func(r map[string]any) { r["zone"] = num("5") }),
		bad("known text field with a pipe", 4, "zone", "|", func(r map[string]any) { r["zone"] = "a|b" }),
		bad("known text field too long", 4, "zone", "at most 512", func(r map[string]any) { r["zone"] = strings.Repeat("z", 513) }),
		good("known text field null", func(r map[string]any) { r["zone"] = nil }),
		bad("known number field with text", 3, "played", "finite number", func(r map[string]any) { r["played"] = "5000" }),
		{"known number field with a float", func(d map[string]any) { record(d, 2)["played"] = num("5000.25") }, "", 0, "", ""},
		bad("unknown kind with a key that starts with an underscore", 8, "_zed", "allowed key", func(r map[string]any) { r["_zed"] = "a" }),
		bad("unknown kind with a list value", 8, "zed", "text, a number or null", func(r map[string]any) { r["zed"] = []any{} }),
		bad("unknown kind with a key that has a dash", 8, "a-b", "allowed key", func(r map[string]any) { r["a-b"] = "a" }),
		bad("unknown kind with a key of 33 characters", 8, strings.Repeat("a", 33), "allowed key", func(r map[string]any) { r[strings.Repeat("a", 33)] = "a" }),
		bad("unknown kind with a __proto__ key", 8, "__proto__", "allowed key", func(r map[string]any) { r["__proto__"] = "a" }),
		bad("unknown kind with long text", 8, "zed", "at most 512", func(r map[string]any) { r["zed"] = strings.Repeat("z", 513) }),
		bad("record with 49 keys", 4, "", "at most 48", func(r map[string]any) {
			for i := range 49 {
				r[fmt.Sprintf("k%d", i)] = "x"
			}
		}),
		{"record is a list", func(d map[string]any) { d["journey"].([]any)[2] = []any{} }, "journey", 3, "", "object"},
	})
}

func TestUnknownKindWithGenericFieldsPasses(t *testing.T) {
	d := goodDoc(t)
	r := record(d, 7)
	r["zed"] = "text"
	r["count"] = num("2.5")
	r["gone"] = nil
	r["Level_2"] = num("1")
	if up, problems := readJSON(t, marshal(t, d), testLimits()); up == nil || len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
}

func TestEveryCatalogFieldTypeIsChecked(t *testing.T) {
	d := goodDoc(t)
	d["journey"] = []any{map[string]any{"addon": "Memories_Economy", "k": "ah", "p": nil, "t": num("1793530000"), "act": "buy", "copper": num("12"), "item": "x"}}
	if up, problems := readJSON(t, marshal(t, d), testLimits()); up == nil || len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	d["journey"].([]any)[0].(map[string]any)["copper"] = "12"
	_, problems := readJSON(t, marshal(t, d), testLimits())
	if len(problems) != 1 || problems[0].Field != "copper" {
		t.Fatalf("problems: %+v", problems)
	}
}

func TestTrailRules(t *testing.T) {
	bad := func(name, field, reason string, mutate func(c map[string]any)) mutation {
		return mutation{name, func(d map[string]any) { mutate(chunk(d, 0)) }, "trail", 1, field, reason}
	}
	good := func(name string, mutate func(c map[string]any)) mutation {
		return mutation{name: name, mutate: func(d map[string]any) { mutate(chunk(d, 0)) }}
	}
	pt := func(t, x, y string, flags any) []any { return []any{num(t), num(x), num(y), flags} }
	withPts := func(n string, pts ...[]any) func(c map[string]any) {
		return func(c map[string]any) {
			list := make([]any, len(pts))
			for i, p := range pts {
				list[i] = p
			}
			c["n"] = num(n)
			c["pts"] = list
		}
	}
	runMutations(t, []mutation{
		good("s null", func(c map[string]any) { c["s"] = nil }),
		bad("s is a float", "s", "whole number or null", func(c map[string]any) { c["s"] = num("1.5") }),
		bad("s is text", "s", "whole number or null", func(c map[string]any) { c["s"] = "x" }),
		bad("t is text", "t", "whole number", func(c map[string]any) { c["t"] = "x" }),
		bad("m negative", "m", "0 to 100000", func(c map[string]any) { c["m"] = num("-1") }),
		bad("m null", "m", "whole number", func(c map[string]any) { c["m"] = nil }),
		bad("n above the limit", "n", "0 to 20000", func(c map[string]any) { c["n"] = num("20001") }),
		bad("n differs from the points", "pts", "n says", func(c map[string]any) { c["n"] = num("2") }),
		bad("pts is not a list", "pts", "list of points", func(c map[string]any) { c["pts"] = "x" }),
		bad("unknown key", "d", "trail chunk", func(c map[string]any) { c["d"] = "x" }),
		bad("missing key", "pts", "missing", func(c map[string]any) { delete(c, "pts") }),
		bad("missing s", "s", "missing", func(c map[string]any) { delete(c, "s") }),
		good("no points", withPts("0")),
		good("flags dash", withPts("1", pt("5", "1", "2", "-"))),
		good("flags empty", withPts("1", pt("5", "1", "2", ""))),
		good("flags of 8 letters", withPts("1", pt("5", "1", "2", "tfmgdwci"))),
		good("point at 0 and 10000", withPts("2", pt("5", "0", "0", "m"), pt("5", "10000", "10000", "m"))),
		bad("flags upper case", "pts[0][3]", "lower-case", withPts("1", pt("5", "1", "2", "M"))),
		bad("flags of 9 letters", "pts[0][3]", "lower-case", withPts("1", pt("5", "1", "2", "abcdefghi"))),
		bad("flags is a number", "pts[0][3]", "lower-case", withPts("1", pt("5", "1", "2", num("1")))),
		bad("x above 10000", "pts[0][1]", "0 to 10000", withPts("1", pt("5", "10001", "2", "m"))),
		bad("y negative", "pts[0][2]", "0 to 10000", withPts("1", pt("5", "1", "-1", "m"))),
		bad("x is a float", "pts[0][1]", "whole number", withPts("1", pt("5", "1.5", "2", "m"))),
		bad("time is a float", "pts[0][0]", "whole number", withPts("1", pt("5.5", "1", "2", "m"))),
		bad("time is negative", "pts[0][0]", "0 or more", withPts("1", pt("-5", "1", "2", "m"))),
		bad("point with 3 values", "pts[0]", "4 values", withPts("1", []any{num("5"), num("1"), num("2")})),
		bad("point is a number", "pts[0]", "4 values", func(c map[string]any) { c["n"] = num("1"); c["pts"] = []any{num("1")} }),
		bad("times go back", "pts[1]", "time order", withPts("2", pt("9", "1", "2", "m"), pt("8", "1", "2", "m"))),
		good("equal times", withPts("2", pt("9", "1", "2", "m"), pt("9", "1", "2", "m"))),
		{"chunk is a number", func(d map[string]any) { d["trail"] = []any{num("1")} }, "trail", 1, "", "object"},
	})
}

func TestEmptyJourneyAndTrailPass(t *testing.T) {
	d := goodDoc(t)
	d["journey"], d["trail"] = []any{}, []any{}
	up, problems := readJSON(t, marshal(t, d), testLimits())
	if up == nil || len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	if got, _ := up.JourneyJSONL(); len(got) != 0 {
		t.Errorf("journey = %q, want nothing", got)
	}
	if got, _ := up.TrailJSONL(); len(got) != 0 {
		t.Errorf("trail = %q, want nothing", got)
	}
}

func TestRecordWithOnlyTheBaseFieldsPasses(t *testing.T) {
	d := goodDoc(t)
	d["journey"] = []any{map[string]any{"addon": "Memories", "k": "out", "p": nil, "t": num("1793530000")}}
	up, problems := readJSON(t, marshal(t, d), testLimits())
	if up == nil || len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	got, _ := up.JourneyJSONL()
	if want := `{"addon":"Memories","k":"out","p":null,"t":1793530000}` + "\n"; string(got) != want {
		t.Errorf("journey = %s, want %s", got, want)
	}
}

func TestNameWithNoSlugUsesTheGUID(t *testing.T) {
	d := goodDoc(t)
	character(d)["name"] = "ÑÑ"
	up, problems := readJSON(t, marshal(t, d), testLimits())
	if up == nil || len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	if up.Name != "nn" {
		t.Errorf("Name = %q, want nn", up.Name)
	}
	character(d)["name"] = "日本"
	up, problems = readJSON(t, marshal(t, d), testLimits())
	if up == nil || len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
	if up.Name != "player-1234-0abcdef0" {
		t.Errorf("Name = %q, want the GUID slug", up.Name)
	}
}

func TestRealmWithNoSlugIsRejected(t *testing.T) {
	d := goodDoc(t)
	character(d)["realm"] = "日本"
	_, problems := readJSON(t, marshal(t, d), testLimits())
	if len(problems) != 1 || problems[0].Field != "realm" || problems[0].File != "character" {
		t.Fatalf("problems: %+v", problems)
	}
}

func TestStreamProblems(t *testing.T) {
	doc := marshal(t, goodDoc(t))
	gz := gzipBytes(t, doc)
	lim := testLimits()
	tests := []struct {
		name   string
		body   []byte
		reason string
	}{
		{"not gzip", doc, "not a gzip file"},
		{"empty body", nil, "not a gzip file"},
		{"truncated gzip", gz[:len(gz)/2], "ends too early"},
		{"truncated checksum", gz[:len(gz)-3], "ends too early"},
		{"damaged gzip", append(append([]byte{}, gz[:len(gz)-6]...), 0, 0, 0, 0, 0, 0, 0, 0), "damaged"},
		{"garbage after the gzip stream", append(append([]byte{}, gz...), "garbage"...), "damaged"},
		{"json with a BOM", gzipBytes(t, append([]byte("\xef\xbb\xbf"), doc...)), "not valid JSON"},
		{"truncated json", gzipBytes(t, doc[:len(doc)/2]), "ends too early"},
		{"not json", gzipBytes(t, []byte("hello")), "not valid JSON"},
		{"json list", gzipBytes(t, []byte("[]")), "one JSON object"},
		{"json text", gzipBytes(t, []byte(`"x"`)), "one JSON object"},
		{"empty json", gzipBytes(t, nil), "ends too early"},
		{"trailing value", gzipBytes(t, append(append([]byte{}, doc...), []byte(" {}")...)), "more data after"},
		{"trailing junk", gzipBytes(t, append(append([]byte{}, doc...), []byte("x")...)), "more data after"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			up, problems := Read(bytes.NewReader(tc.body), lim, testNow)
			if up != nil || len(problems) != 1 || !strings.Contains(problems[0].Reason, tc.reason) {
				t.Fatalf("up = %v, problems = %+v, want one problem with %q", up != nil, problems, tc.reason)
			}
			if problems[0].Code != CodeInvalid || TooLarge(problems) {
				t.Errorf("code = %q", problems[0].Code)
			}
		})
	}
}

func TestTrailingWhitespaceIsFine(t *testing.T) {
	doc := append(marshal(t, goodDoc(t)), " \n\n"...)
	if up, problems := readJSON(t, doc, testLimits()); up == nil || len(problems) > 0 {
		t.Fatalf("problems: %+v", problems)
	}
}

func TestTopLevelProblems(t *testing.T) {
	tests := []struct {
		name  string
		doc   string
		file  string
		field string
		text  string
	}{
		{"duplicate top key", `{"character":{},"character":{},"journey":[],"trail":[]}`, "", "character", "twice"},
		{"unknown top key", `{"extra":1,"journey":[],"trail":[]}`, "", "extra", "not a part of an upload"},
		{"no journey", `{"character":{},"trail":[]}`, "journey", "", "no journey"},
		{"no trail", `{"character":{},"journey":[]}`, "trail", "", "no trail"},
		{"no character", `{"journey":[],"trail":[]}`, "character", "", "no character"},
		{"journey is an object", `{"journey":{"a":[1]},"trail":[]}`, "journey", "", "Must be a list"},
		{"trail is null", `{"journey":[],"trail":null}`, "trail", "", "Must be a list"},
		{"duplicate key in a record", `{"journey":[{"t":1,"t":2}],"trail":[]}`, "journey", "t", "twice"},
		{"duplicate key in the character", `{"character":{"a":1,"a":2},"journey":[],"trail":[]}`, "character", "a", "twice"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			up, problems := readJSON(t, []byte(tc.doc), testLimits())
			if up != nil {
				t.Fatal("got an upload")
			}
			for _, p := range problems {
				if p.File == tc.file && p.Field == tc.field && strings.Contains(p.Reason, tc.text) {
					return
				}
			}
			t.Fatalf("want file %q field %q with %q, got %+v", tc.file, tc.field, tc.text, problems)
		})
	}
}

func TestDuplicateKeyInAGoodUploadIsRejected(t *testing.T) {
	doc := string(marshal(t, goodDoc(t)))
	doc = strings.Replace(doc, `"sex":3`, `"sex":3,"sex":3`, 1)
	if up, problems := readJSON(t, []byte(doc), testLimits()); up != nil || len(problems) != 1 {
		t.Fatalf("got up %v, problems %+v", up != nil, problems)
	}
}

func TestDepthLimit(t *testing.T) {
	deep := func(levels int) string {
		return strings.Repeat("[", levels) + strings.Repeat("]", levels)
	}
	tests := []struct {
		name string
		doc  string
		ok   bool
	}{
		// The top object is level 1, so a value under "x" starts at level 2.
		{"15 nested lists under a key", `{"x":` + deep(15) + `,"journey":[],"trail":[]}`, true},
		{"16 nested lists under a key", `{"x":` + deep(16) + `,"journey":[],"trail":[]}`, false},
		{"very deep", `{"x":` + deep(5000) + `,"journey":[],"trail":[]}`, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, problems := readJSON(t, []byte(tc.doc), testLimits())
			depth := false
			for _, p := range problems {
				depth = depth || strings.Contains(p.Reason, "levels of objects")
			}
			if depth == tc.ok {
				t.Fatalf("depth problem = %v, want %v; problems %+v", depth, !tc.ok, problems)
			}
		})
	}
}

func TestSizeLimit(t *testing.T) {
	doc := marshal(t, goodDoc(t))
	lim := testLimits()
	lim.MaxDecodedBytes = int64(len(doc))
	if up, problems := readJSON(t, doc, lim); up == nil {
		t.Fatalf("an upload of exactly the limit failed: %+v", problems)
	}
	lim.MaxDecodedBytes = int64(len(doc)) - 1
	up, problems := readJSON(t, doc, lim)
	if up != nil || !TooLarge(problems) || len(problems) != 1 {
		t.Fatalf("up %v, problems %+v, want one too_large", up != nil, problems)
	}
}

func TestOutOfRangeTimeDoesNotFlagTheRecordsAfterIt(t *testing.T) {
	d := goodDoc(t)
	record(d, 3)["t"] = num("9999999999")
	_, problems := readJSON(t, marshal(t, d), testLimits())
	if len(problems) != 1 || problems[0].Line != 4 || problems[0].Field != "t" {
		t.Fatalf("want one problem on the t of record 4, got %+v", problems)
	}
}

func TestBodyOverTheRequestLimitIsTooLarge(t *testing.T) {
	body := gzipBytes(t, marshal(t, goodDoc(t)))
	for _, limit := range []int64{int64(len(body)) - 10, 4} {
		r := http.MaxBytesReader(httptest.NewRecorder(), io.NopCloser(bytes.NewReader(body)), limit)
		up, problems := Read(r, testLimits(), testNow)
		if up != nil || !TooLarge(problems) || len(problems) != 1 {
			t.Fatalf("limit %d: up %v, problems %+v, want one too_large", limit, up != nil, problems)
		}
	}
}

func TestGzipBombStopsAtTheLimit(t *testing.T) {
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	zw.Write([]byte(`{"character":{"a":"`))
	zero := bytes.Repeat([]byte("a"), 1<<20)
	for range 200 {
		zw.Write(zero)
	}
	zw.Close()
	if buf.Len() > 1<<20 {
		t.Fatalf("the test bomb is %d bytes", buf.Len())
	}
	lim := testLimits()
	lim.MaxDecodedBytes = 4 << 20
	up, problems := Read(&buf, lim, testNow)
	if up != nil || !TooLarge(problems) {
		t.Fatalf("up %v, problems %+v", up != nil, problems)
	}
}

func TestProblemCap(t *testing.T) {
	d := goodDoc(t)
	list := make([]any, 100)
	for i := range list {
		list[i] = map[string]any{"t": "x"}
	}
	d["journey"] = list
	up, problems := readJSON(t, marshal(t, d), testLimits())
	if up != nil || len(problems) != MaxProblems {
		t.Fatalf("up %v, %d problems, want %d", up != nil, len(problems), MaxProblems)
	}
	lines := map[int]bool{}
	for _, p := range problems {
		lines[p.Line] = true
	}
	if len(lines) == 0 || lines[0] || lines[100] {
		t.Errorf("lines = %v, want the first records only", lines)
	}
}

func TestCountLimits(t *testing.T) {
	lim := testLimits()
	lim.MaxRecords, lim.MaxChunks, lim.MaxPoints = 2, 1, 2
	d := goodDoc(t)
	_, problems := readJSON(t, marshal(t, d), lim)
	want := map[string]bool{"journey": false, "trail": false}
	for _, p := range problems {
		if strings.Contains(p.Reason, "more than") {
			want[p.File] = true
		}
	}
	if !want["journey"] {
		t.Errorf("no record limit problem: %+v", problems)
	}

	d["journey"] = d["journey"].([]any)[:2]
	d["trail"] = []any{chunk(d, 0), chunk(d, 0)}
	_, problems = readJSON(t, marshal(t, d), lim)
	if len(problems) == 0 || problems[len(problems)-1].File != "trail" || !strings.Contains(problems[len(problems)-1].Reason, "more than 1") {
		t.Errorf("no chunk limit problem: %+v", problems)
	}

	d["trail"] = d["trail"].([]any)[:1]
	_, problems = readJSON(t, marshal(t, d), lim)
	if len(problems) != 1 || problems[0].Field != "n" {
		t.Errorf("want one problem for n above MaxPoints, got %+v", problems)
	}
}

func TestMaxTextIsConfigurable(t *testing.T) {
	lim := testLimits()
	lim.MaxText = 8
	d := goodDoc(t)
	_, problems := readJSON(t, marshal(t, d), lim)
	found := false
	for _, p := range problems {
		found = found || (p.File == "journey" && strings.Contains(p.Reason, "at most 8"))
	}
	if !found {
		t.Errorf("no text limit problem: %+v", problems)
	}
}

func TestProblemJSON(t *testing.T) {
	b, err := json.Marshal(Problem{File: "journey", Line: 3, Field: "t", Reason: "Bad.", Code: CodeInvalid})
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != `{"file":"journey","line":3,"field":"t","reason":"Bad."}` {
		t.Errorf("json = %s", b)
	}
}

func TestStoredFilesAreWrittenByTheServer(t *testing.T) {
	d := goodDoc(t)
	raw := string(marshal(t, d))
	// Uploaded bytes are reformatted: a pretty-printed upload gives the same stored bytes as a compact one.
	pretty, err := json.MarshalIndent(d, "", "    ")
	if err != nil {
		t.Fatal(err)
	}
	a, p1 := readJSON(t, []byte(raw), testLimits())
	b, p2 := readJSON(t, pretty, testLimits())
	if a == nil || b == nil {
		t.Fatalf("problems: %+v %+v", p1, p2)
	}
	for _, write := range []func(*Upload) ([]byte, error){(*Upload).CharacterJSON, (*Upload).JourneyJSONL, (*Upload).TrailJSONL} {
		x, _ := write(a)
		y, _ := write(b)
		if !bytes.Equal(x, y) {
			t.Errorf("stored bytes depend on the upload layout:\n%s\n%s", x, y)
		}
	}
}

func TestRecordHelpers(t *testing.T) {
	r := Record{"t": num("5"), "k": "zo", "m": num("1")}
	if _, ok := r.JSONValue().(map[string]any); !ok {
		t.Error("JSONValue is not a map")
	}
}

func TestTooLargeIgnoresOtherProblems(t *testing.T) {
	if TooLarge([]Problem{{Code: CodeInvalid}}) || TooLarge(nil) {
		t.Error("TooLarge is true for invalid-only problems")
	}
}

func TestTokenBudgetStopsAHugeValue(t *testing.T) {
	lim := testLimits()
	d := goodDoc(t)
	huge := make([]any, characterTokens)
	for i := range huge {
		huge[i] = num("0")
	}
	d["character"].(map[string]any)["sessions"] = huge
	up, problems := readJSON(t, marshal(t, d), lim)
	if up != nil || len(problems) != 1 || problems[0].File != "character" || !strings.Contains(problems[0].Reason, "JSON values") {
		t.Errorf("want one token budget problem, got %+v", problems)
	}

	d = goodDoc(t)
	c := chunk(d, 0)
	pts := make([]any, lim.MaxPoints*2)
	for i := range pts {
		pts[i] = []any{num("1"), num("1"), num("1"), "-"}
	}
	c["pts"], c["n"] = pts, num("1")
	_, problems = readJSON(t, marshal(t, d), lim)
	if len(problems) != 1 || problems[0].File != "trail" || !strings.Contains(problems[0].Reason, "JSON values") {
		t.Errorf("want one token budget problem for the chunk, got %+v", problems)
	}
}

func TestLongKeysAreCutInProblems(t *testing.T) {
	key := strings.Repeat("é", 5000)
	d := goodDoc(t)
	d[key] = num("1")
	character(d)["addons"].(map[string]any)["Memories"].(map[string]any)["counts"] = map[string]any{key: num("1")}
	_, problems := readJSON(t, marshal(t, d), testLimits())
	if len(problems) != 2 {
		t.Fatalf("want 2 problems, got %d", len(problems))
	}
	for _, p := range problems {
		if len(p.Field) > maxField+len("…") || !strings.HasSuffix(p.Field, "…") || !utf8.ValidString(p.Field) || strings.Contains(p.Reason, "éé") {
			t.Errorf("problem echoes the long key: field %d bytes, reason %q", len(p.Field), p.Reason)
		}
	}
}
