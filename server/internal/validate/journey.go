package validate

import (
	"fmt"
	"regexp"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
	"github.com/fmartingr/wow-addon-memories/server/internal/kinds"
)

var (
	unknownKindPattern = regexp.MustCompile(`^[a-z][a-z0-9]{0,7}$`)
	unknownKeyPattern  = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]{0,31}$`)
	extraKeyPattern    = regexp.MustCompile(`^[1-9][0-9]{0,2}$`)

	// ScreenshotPattern is the form of the screenshot field of a record: a game screenshot in the screenshots folder.
	ScreenshotPattern = regexp.MustCompile(`^screenshots/WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png|tga)$`)
)

// Record is one journal record, as the gather writes it. Its values are json.Number, string, nil, and for extra and
// notes a map and a list.
type Record map[string]any

// JSONValue makes a Record writable by jsonw, with its keys sorted.
func (r Record) JSONValue() any { return map[string]any(r) }

// journalState carries what one record needs to know of the records before it.
type journalState struct {
	prevT int64
	now   int64
}

// record checks one journal record and returns it with the key order that the stored file needs.
func (ck *checker) record(v any, st *journalState) Record {
	m, ok := v.(map[string]any)
	if !ok {
		ck.fail("", "Must be an object.")
		return nil
	}
	if len(m) > maxRecordKeys && !ck.lim.stored {
		ck.fail("", "Has %d keys, but at most %d are allowed.", len(m), maxRecordKeys)
		return nil
	}
	for _, k := range []string{"t", "p", "k", "addon"} {
		if _, ok := m[k]; !ok {
			ck.fail(k, "Is missing.")
		}
	}
	out := make(Record, len(m))
	var kind kinds.Kind
	var known bool
	if k, ok := m["k"]; ok {
		kind, known = ck.kind(k)
	}
	for _, key := range sortedKeys(m) {
		if ck.col.full() {
			break
		}
		v := m[key]
		out[key] = v
		switch key {
		case "t":
			// An out-of-range t does not move prevT, so one bad time cannot flag every record after it.
			if r := intReason(v, minTime, st.now+timeSlack); r != "" {
				ck.fail(key, "%s", r)
			} else {
				t, _ := integer(v)
				if t < st.prevT {
					ck.fail(key, "Is earlier than the record before it. Records must be in time order.")
				}
				st.prevT = t
			}
		case "p":
			ck.integerOrNull(key, v, 0, 1e10)
		case "m":
			ck.integerOrNull(key, v, 0, 100_000)
		case "x", "y":
			ck.numberOrNull(key, v, 0, 10_000)
		case "k":
		case "addon":
			ck.pattern(key, v, addonPattern, "the name of an addon")
		case "session":
			ck.integerOrNull(key, v, 1, 1e9)
		case "extra":
			ck.extra(v)
		case "notes":
			out[key] = ck.notes(v)
		case "screenshot":
			ck.pattern(key, v, ScreenshotPattern, "a screenshot path like screenshots/WoWScrnShot_110126_114820.jpg")
		default:
			ck.field(key, v, kind, known)
		}
	}
	return out
}

// kind checks k and returns its catalog entry. known is false for a kind that this server does not list yet.
func (ck *checker) kind(v any) (kind kinds.Kind, known bool) {
	s, ok := v.(string)
	if !ok {
		ck.fail("k", "Must be text.")
		return kinds.Kind{}, false
	}
	// Stored records passed the catalog of their upload. A later catalog may list their kind with other fields, so
	// stored records get the generic check, or a catalog change would lock the character out.
	if kind, known = kinds.Lookup(s); known && !ck.lim.stored {
		return kind, true
	}
	if !unknownKindPattern.MatchString(s) {
		ck.fail("k", "Is not a kind that this server knows, and it is not a valid new kind name. A kind is 1 to 8 lower-case letters and digits.")
	}
	return kinds.Kind{}, false
}

// field checks a key that is not one of the base keys. A known kind lists its fields; an unknown kind gets a
// generic check, so a kind of a newer addon still uploads.
func (ck *checker) field(key string, v any, kind kinds.Kind, known bool) {
	if !known {
		if !unknownKeyPattern.MatchString(key) {
			ck.fail(key, "Is not an allowed key. A key starts with a letter and has at most 32 letters, digits and underscores.")
			return
		}
		switch v.(type) {
		case nil:
		case string:
			ck.text(key, v, 0, 0)
		default:
			if _, ok := number(v); !ok {
				ck.fail(key, "Must be text, a number or null.")
			}
		}
		return
	}
	typ, ok := kind.Fields[key]
	switch {
	case !ok:
		ck.fail(key, "Is not a field of this kind.")
	case v == nil:
	case typ == kinds.Number:
		if _, ok := number(v); !ok {
			ck.fail(key, "Must be a finite number or null.")
		}
	default:
		ck.text(key, v, 0, 0)
	}
}

func (ck *checker) extra(v any) {
	m, ok := v.(map[string]any)
	if !ok {
		ck.fail("extra", "Must be an object.")
		return
	}
	for _, k := range sortedKeys(m) {
		if !extraKeyPattern.MatchString(k) {
			ck.fail("extra."+k, "Is not an allowed key. A key is a field number from 1 to 999.")
			continue
		}
		ck.text("extra."+k, m[k], 0, 0)
	}
}

// notes checks the screenshot notes and returns them as objects with the keys source, note, in that order.
func (ck *checker) notes(v any) any {
	list, ok := v.([]any)
	if !ok {
		ck.fail("notes", "Must be a list.")
		return v
	}
	if len(list) > maxNotes {
		ck.fail("notes", "Has %d notes, but at most %d are allowed.", len(list), maxNotes)
		return v
	}
	out := make([]any, len(list))
	for i, e := range list {
		field := fmt.Sprintf("notes[%d]", i)
		m, ok := e.(map[string]any)
		if !ok {
			ck.fail(field, "Must be an object with source and note.")
			continue
		}
		for _, k := range sortedKeys(m) {
			if k != "source" && k != "note" {
				ck.fail(field+"."+k, "Is not a part of a note.")
			}
		}
		for _, k := range []string{"source", "note"} {
			if _, ok := m[k]; !ok {
				ck.fail(field+"."+k, "Is missing.")
			} else {
				ck.text(field+"."+k, m[k], 0, 0)
			}
		}
		out[i] = jsonw.Ordered{{Key: "source", Value: m["source"]}, {Key: "note", Value: m["note"]}}
	}
	return out
}
