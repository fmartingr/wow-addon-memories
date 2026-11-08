package kinds

import (
	"reflect"
	"strings"
	"testing"
)

const sample = `# Kinds

| Box | Kinds | Addon |
|---|---|---|
| Gathering: new findings only | ` + "`ga`" + ` | Memories_Gathering |

## Memories

| Kind | Group | Name | Fields |
|---|---|---|---|
| ` + "`in`" + ` | Sessions | Login | ` + "`how`" + ` |
| ` + "`out`" + ` | Sessions | Logout | — |
| ` + "`pl`" + ` | Sessions | Played | ` + "`#played`, `#seconds`, `tag`" + ` |

## Memories_Combat

| Kind | Group | Name | Fields |
|---|---|---|---|
| ` + "`ki`" + ` | Combat | Killed | ` + "`name`, `#npc`" + ` |

### Deaths

| ` + "`xd`" + ` | Combat | Died | — |

## Other section

| ` + "`zz`" + ` | G | N | ` + "`x`" + ` |
`

func TestParseSample(t *testing.T) {
	got, err := Parse(strings.NewReader(sample))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]Kind{
		"in":  {Addon: "Memories", Fields: map[string]FieldType{"how": Text}},
		"out": {Addon: "Memories", Fields: map[string]FieldType{}},
		"pl":  {Addon: "Memories", Fields: map[string]FieldType{"played": Number, "seconds": Number, "tag": Text}},
		"ki":  {Addon: "Memories_Combat", Fields: map[string]FieldType{"name": Text, "npc": Number}},
		"xd":  {Addon: "Memories_Combat", Fields: map[string]FieldType{}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Parse = %v, want %v", got, want)
	}
	b, err := Marshal(got)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(b), "{\n  \"in\": {") || !strings.HasSuffix(string(b), "}\n") {
		t.Errorf("Marshal = %q", b)
	}
}

func TestParseErrors(t *testing.T) {
	tests := []struct{ name, md, want string }{
		{"empty", "# Kinds\n", "no kind found"},
		{"duplicate kind", "## Memories\n| `in` | G | N | — |\n| `in` | G | N | — |\n", "listed twice"},
		{"duplicate field", "## Memories\n| `in` | G | N | `a`, `#a` |\n", "twice"},
		{"no field and no dash", "## Memories\n| `in` | G | N |  |\n", "no field"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(strings.NewReader(tc.md))
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v, want it to contain %q", err, tc.want)
			}
		})
	}
}

func TestLookup(t *testing.T) {
	k, ok := Lookup("pl")
	if !ok || k.Addon != "Memories" || k.Fields["played"] != Number {
		t.Errorf("Lookup(pl) = %v, %v", k, ok)
	}
	k, ok = Lookup("ki")
	if !ok || k.Addon != "Memories_Combat" || k.Fields["name"] != Text || k.Fields["npc"] != Number {
		t.Errorf("Lookup(ki) = %v, %v", k, ok)
	}
	if k, ok := Lookup("out"); !ok || len(k.Fields) != 0 {
		t.Errorf("Lookup(out) = %v, %v, want a kind with no field", k, ok)
	}
	if _, ok := Lookup("zz"); ok {
		t.Error("Lookup(zz) found an unknown kind")
	}
}

func TestAddons(t *testing.T) {
	want := []string{"Memories", "Memories_Character", "Memories_Combat", "Memories_Economy", "Memories_Gathering", "Memories_Social"}
	if got := Addons(); !reflect.DeepEqual(got, want) {
		t.Errorf("Addons = %v, want %v", got, want)
	}
}

func TestCatalogHasEveryKind(t *testing.T) {
	if n := len(catalog()); n != 75 {
		t.Errorf("the catalog has %d kinds, want 75", n)
	}
}
