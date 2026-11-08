// Package kinds is the catalog of journal kinds. kinds.json is made from docs/kinds.md by `go generate`, and a test
// fails when it is stale.
package kinds

import (
	_ "embed"
	"encoding/json"
	"sort"
	"sync"
)

//go:generate go run ./gen ../../../docs/kinds.md kinds.json

// FieldType is the JSON type of a kind field.
type FieldType string

const (
	Number FieldType = "number"
	Text   FieldType = "text"
)

// Kind is one journal kind: the addon that writes it and its named fields.
type Kind struct {
	Addon  string               `json:"addon"`
	Fields map[string]FieldType `json:"fields"`
}

//go:embed kinds.json
var catalogJSON []byte

var catalog = sync.OnceValue(func() map[string]Kind {
	var m map[string]Kind
	if err := json.Unmarshal(catalogJSON, &m); err != nil {
		panic("kinds.json is damaged: " + err.Error())
	}
	return m
})

// Lookup returns the kind named k.
func Lookup(k string) (Kind, bool) {
	kind, ok := catalog()[k]
	return kind, ok
}

// Addons returns the names of the addons that write kinds, sorted.
func Addons() []string {
	seen := map[string]bool{}
	var out []string
	for _, k := range catalog() {
		if !seen[k.Addon] {
			seen[k.Addon] = true
			out = append(out, k.Addon)
		}
	}
	sort.Strings(out)
	return out
}
