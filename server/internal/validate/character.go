package validate

import (
	"fmt"
	"maps"
	"regexp"
	"slices"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
)

var (
	guidPattern   = regexp.MustCompile(`^Player-[0-9]{1,6}-[0-9A-F]{8}$`)
	regionPattern = regexp.MustCompile(`^[A-Z]{2}$`)
	// A flavor is the game folder without its outer underscores, so "classic_era" is real.
	flavorPattern  = regexp.MustCompile(`^[a-z0-9]{1,32}(_[a-z0-9]{1,32})*$`)
	addonPattern   = regexp.MustCompile(`^[A-Za-z0-9_]{1,64}$`)
	charKeyPattern = regexp.MustCompile(`^[a-z][A-Za-z0-9]{0,31}$`)
	flagKeyPattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9]{0,31}$`)
	firstKeys      = map[string]bool{"level": true, "m": true, "played": true, "t": true, "x": true, "y": true}
	sessionInts    = map[string]bool{"last": true, "played0": true, "played1": true, "tz": true}
	requiredChar   = []string{"guid", "name", "region", "flavor", "realm", "realmLabel", "level", "class", "race", "faction", "sex", "flags", "sessions", "addons"}
)

const maxFlavorLength = 32

func sortedKeys(m map[string]any) []string { return slices.Sorted(maps.Keys(m)) }

func (ck *checker) pattern(field string, v any, re *regexp.Regexp, what string) {
	s, ok := v.(string)
	if !ok || !re.MatchString(s) {
		ck.fail(field, "Must be %s.", what)
	}
}

// character checks character.json and returns its content with the key order that the stored file needs.
func (ck *checker) character(v any) map[string]any {
	doc, ok := v.(map[string]any)
	if !ok {
		ck.fail("", "Must be an object.")
		return nil
	}
	out := make(map[string]any, len(doc))
	if len(doc) > maxCharKeys {
		ck.fail("", "Has %d keys, but at most %d are allowed.", len(doc), maxCharKeys)
	}
	for _, k := range requiredChar {
		if _, ok := doc[k]; !ok {
			ck.fail(k, "Is missing.")
		}
	}
	budget := maxTreeValues
	for _, k := range sortedKeys(doc) {
		if ck.col.full() {
			break
		}
		v := doc[k]
		out[k] = v
		switch k {
		case "guid":
			ck.pattern(k, v, guidPattern, "a player GUID like Player-1234-0ABCDEF0")
		case "name":
			ck.text(k, v, 1, 48)
		case "region":
			ck.pattern(k, v, regionPattern, "two upper-case letters, like EU")
		case "flavor":
			if s, ok := v.(string); !ok || len(s) > maxFlavorLength || !flavorPattern.MatchString(s) {
				ck.fail(k, "Must be the game version in lower case, like retail or classic_era.")
			}
		case "realm", "realmLabel":
			ck.text(k, v, 1, 64)
		case "level":
			ck.integer(k, v, 1, 100)
		case "class", "race", "faction":
			ck.text(k, v, 1, 64)
		case "sex":
			ck.integer(k, v, 0, 3)
		case "first":
			ck.first(v)
		case "flags":
			ck.flags(v)
		case "sessions":
			ck.sessions(v)
		case "addons":
			out[k] = ck.addons(v, &budget)
		default:
			ck.extraKey(k, v)
		}
	}
	return out
}

// extraKey checks a key that no rule names, such as "surname".
func (ck *checker) extraKey(k string, v any) {
	if !charKeyPattern.MatchString(k) {
		ck.fail(k, "Is not an allowed key. A key starts with a lower-case letter and has at most 32 letters and digits.")
		return
	}
	switch v.(type) {
	case nil, bool:
	case string:
		ck.text(k, v, 0, 0)
	default:
		if _, ok := number(v); !ok {
			ck.fail(k, "Must be text, a number, true, false or null.")
		}
	}
}

func (ck *checker) first(v any) {
	m, ok := v.(map[string]any)
	if !ok {
		ck.fail("first", "Must be an object.")
		return
	}
	for _, k := range sortedKeys(m) {
		field := "first." + k
		switch {
		case firstKeys[k]:
			ck.numberOrNull(field, m[k], -1e12, 1e12)
		case k == "wait":
			// The addon keeps wait until the first /played answer dates the first login.
			if _, ok := m[k].(bool); !ok && m[k] != nil {
				ck.fail(field, "Must be true, false or null.")
			}
		default:
			ck.fail(field, "Is not a part of the first record.")
		}
	}
}

func (ck *checker) flags(v any) {
	m, ok := v.(map[string]any)
	if !ok {
		ck.fail("flags", "Must be an object.")
		return
	}
	if len(m) > maxCharKeys {
		ck.fail("flags", "Has %d flags, but at most %d are allowed.", len(m), maxCharKeys)
	}
	for _, k := range sortedKeys(m) {
		field := "flags." + k
		if !flagKeyPattern.MatchString(k) {
			ck.fail(field, "Is not an allowed flag name.")
		} else if _, ok := m[k].(bool); !ok {
			ck.fail(field, "Must be true or false.")
		}
	}
}

func (ck *checker) sessions(v any) {
	list, ok := v.([]any)
	if !ok {
		ck.fail("sessions", "Must be a list.")
		return
	}
	if len(list) > maxSessions {
		ck.fail("sessions", "Has %d sessions, but at most %d are allowed.", len(list), maxSessions)
		return
	}
	for i, e := range list {
		if ck.col.full() {
			return
		}
		prefix := fmt.Sprintf("sessions[%d]", i)
		m, ok := e.(map[string]any)
		if !ok {
			ck.fail(prefix, "Must be an object.")
			continue
		}
		if _, ok := m["start"]; !ok {
			ck.fail(prefix+".start", "Is missing.")
		}
		for _, k := range sortedKeys(m) {
			field := prefix + "." + k
			switch {
			case k == "start":
				ck.integer(field, m[k], 0, 1e11)
			case k == "computer" || k == "how":
				if m[k] != nil {
					ck.text(field, m[k], 0, 0)
				}
			case sessionInts[k]:
				// played0 is -1 when the first /played answer came after the login.
				ck.integerOrNull(field, m[k], -1e10, 1e11)
			default:
				ck.fail(field, "Is not a part of a session.")
			}
		}
	}
}

// addons checks the addon entries and returns them with the key order counts, snap, schema, writtenBy.
func (ck *checker) addons(v any, budget *int) any {
	m, ok := v.(map[string]any)
	if !ok {
		ck.fail("addons", "Must be an object.")
		return v
	}
	if len(m) > maxAddons {
		ck.fail("addons", "Has %d addons, but at most %d are allowed.", len(m), maxAddons)
		return v
	}
	out := make(map[string]any, len(m))
	for _, name := range sortedKeys(m) {
		if ck.col.full() {
			break
		}
		field := "addons." + name
		if !addonPattern.MatchString(name) {
			ck.fail(field, "Is not an allowed addon name.")
			continue
		}
		e, ok := m[name].(map[string]any)
		if !ok {
			ck.fail(field, "Must be an object.")
			continue
		}
		for _, k := range sortedKeys(e) {
			switch k {
			case "counts", "snap", "schema", "writtenBy":
			default:
				ck.fail(field+"."+k, "Is not a part of an addon entry.")
			}
		}
		for _, k := range []string{"counts", "snap", "schema", "writtenBy"} {
			if _, ok := e[k]; !ok {
				ck.fail(field+"."+k, "Is missing.")
			}
		}
		for _, k := range []string{"counts", "snap"} {
			if v, ok := e[k]; ok {
				ck.tree(field+"."+k, v, 1, budget)
			}
		}
		if _, ok := e["schema"]; ok {
			ck.integer(field+".schema", e["schema"], 0, 1_000_000)
		}
		if _, ok := e["writtenBy"]; ok {
			ck.text(field+".writtenBy", e["writtenBy"], 1, 64)
		}
		out[name] = jsonw.Ordered{{Key: "counts", Value: e["counts"]}, {Key: "snap", Value: e["snap"]}, {Key: "schema", Value: e["schema"]}, {Key: "writtenBy", Value: e["writtenBy"]}}
	}
	return out
}

// tree checks the counts or snap of an addon: objects of numbers, text and null, a few levels deep. budget is what
// is left of the values that one character may hold.
func (ck *checker) tree(field string, v any, depth int, budget *int) {
	m, ok := v.(map[string]any)
	if !ok {
		ck.fail(field, "Must be an object.")
		return
	}
	if depth > maxTreeDepth {
		ck.fail(field, "Is nested more than %d levels deep.", maxTreeDepth)
		return
	}
	for _, k := range sortedKeys(m) {
		if ck.col.full() {
			return
		}
		*budget--
		if *budget < 0 {
			if *budget == -1 {
				ck.fail(field, "Has more than %d values in all addons.", maxTreeValues)
			}
			return
		}
		child := field + "." + k
		if r := textReason(k, 1, maxTreeKey, true); r != "" || k == "__proto__" {
			ck.fail(child, "Is not an allowed key. A key is text of 1 to %d bytes.", maxTreeKey)
			continue
		}
		switch t := m[k].(type) {
		case nil:
		case map[string]any:
			ck.tree(child, t, depth+1, budget)
		case string:
			if r := textReason(t, 0, maxTreeText, true); r != "" {
				ck.fail(child, "%s", r)
			}
		default:
			if _, ok := number(t); !ok {
				ck.fail(child, "Must be a number, text, an object or null.")
			}
		}
	}
}
