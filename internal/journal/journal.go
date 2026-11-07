// Package journal unpacks and decodes the journal and trail data of the Memories saved files.
package journal

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Field is one named field of a kind. A numeric field holds a number.
type Field struct {
	Name    string
	Numeric bool
}

// Kind describes the fields of one journal kind.
type Kind struct {
	Addon  string
	Group  string
	Fields []Field
}

// Kinds maps a kind to its description.
type Kinds map[string]Kind

// Record is one decoded journal line.
type Record map[string]any

// ErrShortLine is returned for a line with fewer than 6 columns.
var ErrShortLine = errors.New("fewer than 6 columns")

// ErrBadTime is returned for a line whose time column is not a whole number.
var ErrBadTime = errors.New("the time is not a whole number")

var numberPattern = regexp.MustCompile(`^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$`)

// reserved are the keys of a record that are not fields of its kind. The addon reserves only the fixed columns, so a
// field with another of these names goes into "extra".
var reserved = map[string]bool{
	"t": true, "p": true, "m": true, "x": true, "y": true, "k": true,
	"extra": true, "addon": true, "session": true, "screenshot": true, "notes": true,
}

// ParseKinds reads MemoriesDB.kinds, where each value is "addon;group;f1,#f2,...".
func ParseKinds(v any) Kinds {
	out := Kinds{}
	m, ok := v.(map[string]any)
	if !ok {
		return out
	}
	for kind, raw := range m {
		text, ok := raw.(string)
		if !ok {
			continue
		}
		parts := strings.SplitN(text, ";", 3)
		if len(parts) != 3 {
			continue
		}
		k := Kind{Addon: parts[0], Group: parts[1]}
		if parts[2] != "" {
			for _, f := range strings.Split(parts[2], ",") {
				name := strings.TrimPrefix(f, "#")
				k.Fields = append(k.Fields, Field{Name: name, Numeric: name != f})
			}
		}
		out[kind] = k
	}
	return out
}

// List returns the values of a Lua list. The parser turns an empty table, or one with gaps, into a map.
func List(v any) []any {
	switch t := v.(type) {
	case []any:
		return t
	case map[string]any:
		keys := make([]int, 0, len(t))
		for k := range t {
			if n, err := strconv.Atoi(k); err == nil {
				keys = append(keys, n)
			}
		}
		sort.Ints(keys)
		out := make([]any, 0, len(keys))
		for _, k := range keys {
			out = append(out, t[strconv.Itoa(k)])
		}
		return out
	}
	return nil
}

// Lines returns the lines of a journal log: every chunk split on "\n", then the open lines.
func Lines(log any) []string {
	m, ok := log.(map[string]any)
	if !ok {
		return nil
	}
	var out []string
	for _, c := range List(m["chunks"]) {
		if s, ok := c.(string); ok && s != "" {
			out = append(out, strings.Split(s, "\n")...)
		}
	}
	for _, l := range List(m["open"]) {
		if s, ok := l.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

// Number parses the text of a numeric field. It refuses hex, NaN, infinities and other forms that JSON cannot hold.
func Number(s string) (any, bool) {
	if !numberPattern.MatchString(s) {
		return nil, false
	}
	if n, err := strconv.ParseInt(s, 10, 64); err == nil {
		return n, true
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil || math.IsInf(f, 0) {
		return nil, false
	}
	return f, true
}

// Int reads a whole number from a saved-file value or a JSON value.
func Int(v any) (int64, bool) {
	switch n := v.(type) {
	case int64:
		return n, true
	case float64:
		if n == math.Trunc(n) && math.Abs(n) < 1<<53 {
			return int64(n), true
		}
	case json.Number:
		if i, err := n.Int64(); err == nil {
			return i, true
		}
	}
	return 0, false
}

// Decode turns a line "t|p|m|x|y|kind|f1|..." into a record. Named fields come from kinds; an empty field is left out;
// a value past the known fields, or text in a numeric field, goes into "extra" under its 1-based field number.
func Decode(line string, kinds Kinds) (Record, error) {
	cols := strings.Split(line, "|")
	if len(cols) < 6 {
		return nil, ErrShortLine
	}
	t, err := strconv.ParseInt(cols[0], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("%w: %q", ErrBadTime, cols[0])
	}
	rec := Record{"t": t, "k": cols[5]}
	for i, name := range []string{"p", "m", "x", "y"} {
		rec[name] = fixed(cols[i+1])
	}
	spec := kinds[cols[5]]
	extra := map[string]any{}
	for i, v := range cols[6:] {
		if v == "" {
			continue
		}
		if i >= len(spec.Fields) || reserved[spec.Fields[i].Name] {
			extra[strconv.Itoa(i+1)] = v
			continue
		}
		f := spec.Fields[i]
		if !f.Numeric {
			rec[f.Name] = v
		} else if n, ok := Number(v); ok {
			rec[f.Name] = n
		} else {
			extra[strconv.Itoa(i+1)] = v
		}
	}
	if len(extra) > 0 {
		rec["extra"] = extra
	}
	return rec, nil
}

func fixed(s string) any {
	if s == "" {
		return nil
	}
	if n, ok := Number(s); ok {
		return n
	}
	return s
}

// T returns the time of a record.
func (r Record) T() int64 {
	t, _ := Int(r["t"])
	return t
}

// String returns a text field, or "" when it is missing or not text.
func (r Record) String(key string) string {
	s, _ := r[key].(string)
	return s
}
