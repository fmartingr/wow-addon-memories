// Package jsonw writes the stored files in one canonical form: the form of Go's encoding/json encoder with HTML
// escaping off, which is also the form of the Dart gather. The same data always gives the same bytes.
package jsonw

import (
	"bytes"
	"encoding/json"
	"fmt"
	"maps"
	"slices"
	"strconv"
	"unicode/utf8"
)

// Pair is one key and value of an Ordered object.
type Pair struct {
	Key   string
	Value any
}

// Ordered is an object written with its keys in this order. A plain map is written with its keys sorted by their
// UTF-8 bytes.
type Ordered []Pair

// Valuer is a value that turns itself into a writable one when it is written.
type Valuer interface {
	JSONValue() any
}

// Array is a list that is read element by element, so a long list needs no copy.
type Array interface {
	Len() int
	At(i int) any
}

// Marshal writes v as one JSON document and a newline. With indent, each level is indented by one space.
// v may hold nil, bool, int, int64, json.Number, string, map[string]any, []any, Ordered, Valuer and Array.
func Marshal(v any, indent bool) ([]byte, error) {
	w := writer{indent: indent}
	if err := w.value(v, 0); err != nil {
		return nil, err
	}
	w.buf.WriteByte('\n')
	return w.buf.Bytes(), nil
}

// Lines writes n values, one per line with no indent, each followed by a newline: the JSONL form.
func Lines(n int, at func(i int) any) ([]byte, error) {
	w := writer{}
	for i := range n {
		if err := w.value(at(i), 0); err != nil {
			return nil, err
		}
		w.buf.WriteByte('\n')
	}
	return w.buf.Bytes(), nil
}

type writer struct {
	buf    bytes.Buffer
	indent bool
}

func (w *writer) newline(depth int) {
	if !w.indent {
		return
	}
	w.buf.WriteByte('\n')
	for range depth {
		w.buf.WriteByte(' ')
	}
}

func (w *writer) value(v any, depth int) error {
	switch t := v.(type) {
	case nil:
		w.buf.WriteString("null")
	case bool:
		w.buf.WriteString(strconv.FormatBool(t))
	case int:
		w.buf.WriteString(strconv.Itoa(t))
	case int64:
		w.buf.WriteString(strconv.FormatInt(t, 10))
	case json.Number:
		if t == "" {
			t = "0"
		}
		w.buf.WriteString(string(t))
	case string:
		w.str(t)
	case Valuer:
		return w.value(t.JSONValue(), depth)
	case Array:
		return w.list(t.Len(), t.At, depth)
	case []any:
		return w.list(len(t), func(i int) any { return t[i] }, depth)
	case map[string]any:
		pairs := make(Ordered, 0, len(t))
		for _, k := range slices.Sorted(maps.Keys(t)) {
			pairs = append(pairs, Pair{k, t[k]})
		}
		return w.object(pairs, depth)
	case Ordered:
		return w.object(t, depth)
	default:
		return fmt.Errorf("jsonw: cannot write a %T", v)
	}
	return nil
}

func (w *writer) list(n int, at func(int) any, depth int) error {
	if n == 0 {
		w.buf.WriteString("[]")
		return nil
	}
	w.buf.WriteByte('[')
	for i := range n {
		if i > 0 {
			w.buf.WriteByte(',')
		}
		w.newline(depth + 1)
		if err := w.value(at(i), depth+1); err != nil {
			return err
		}
	}
	w.newline(depth)
	w.buf.WriteByte(']')
	return nil
}

func (w *writer) object(pairs Ordered, depth int) error {
	if len(pairs) == 0 {
		w.buf.WriteString("{}")
		return nil
	}
	w.buf.WriteByte('{')
	for i, p := range pairs {
		if i > 0 {
			w.buf.WriteByte(',')
		}
		w.newline(depth + 1)
		w.str(p.Key)
		w.buf.WriteByte(':')
		if w.indent {
			w.buf.WriteByte(' ')
		}
		if err := w.value(p.Value, depth+1); err != nil {
			return err
		}
	}
	w.newline(depth)
	w.buf.WriteByte('}')
	return nil
}

const hexDigits = "0123456789abcdef"

// str escapes like encoding/json with HTML escaping off: the quote, the backslash and the control characters, and
// U+2028 and U+2029 because they break JavaScript. An invalid byte becomes U+FFFD.
func (w *writer) str(s string) {
	w.buf.WriteByte('"')
	for i := 0; i < len(s); {
		c := s[i]
		if c < utf8.RuneSelf {
			switch c {
			case '"':
				w.buf.WriteString(`\"`)
			case '\\':
				w.buf.WriteString(`\\`)
			case '\b':
				w.buf.WriteString(`\b`)
			case '\f':
				w.buf.WriteString(`\f`)
			case '\n':
				w.buf.WriteString(`\n`)
			case '\r':
				w.buf.WriteString(`\r`)
			case '\t':
				w.buf.WriteString(`\t`)
			default:
				if c < 0x20 {
					w.buf.WriteString(`\u00`)
					w.buf.WriteByte(hexDigits[c>>4])
					w.buf.WriteByte(hexDigits[c&0xf])
				} else {
					w.buf.WriteByte(c)
				}
			}
			i++
			continue
		}
		r, size := utf8.DecodeRuneInString(s[i:])
		switch {
		case r == utf8.RuneError && size == 1:
			w.buf.WriteString(`�`)
		case r == ' ' || r == ' ':
			w.buf.WriteString(`\u202`)
			w.buf.WriteByte(hexDigits[r&0xf])
		default:
			w.buf.WriteString(s[i : i+size])
		}
		i += size
	}
	w.buf.WriteByte('"')
}
