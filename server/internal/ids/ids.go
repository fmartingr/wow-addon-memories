// Package ids turns the names of a character into the safe path segments of its web address.
package ids

import (
	"fmt"
	"regexp"
	"strings"

	"golang.org/x/text/unicode/norm"
)

var (
	nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

	// Pattern is the form of every path segment, so a segment is always safe as a folder name and in a URL.
	Pattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
)

// Slug returns the NFKD-normalized ASCII text in lower case, with each run of other characters replaced by "-".
func Slug(s string) string {
	var b strings.Builder
	for _, r := range norm.NFKD.String(s) {
		if r < 0x80 {
			b.WriteRune(r)
		}
	}
	return strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(b.String()), "-"), "-")
}

// PathError says which part of a character cannot make a segment of the address.
type PathError struct {
	Field  string
	Reason string
}

func (e *PathError) Error() string { return e.Reason }

// Path returns the four segments of the address of a decoded character.json:
// the flavor, the region, the realm and the name. A name with no slug falls back to the slug of the GUID.
func Path(character map[string]any) (flavor, region, realm, name string, err error) {
	var raw [5]string
	for i, key := range []string{"flavor", "region", "realm", "name", "guid"} {
		s, ok := character[key].(string)
		if !ok {
			return "", "", "", "", &PathError{key, fmt.Sprintf("The character has no text in %q.", key)}
		}
		raw[i] = s
	}
	flavor, region, realm, name = Slug(raw[0]), strings.ToLower(raw[1]), Slug(raw[2]), Slug(raw[3])
	if name == "" {
		name = Slug(raw[4])
	}
	for _, p := range []struct{ key, value string }{{"flavor", flavor}, {"region", region}, {"realm", realm}, {"name", name}} {
		if !Pattern.MatchString(p.value) {
			return "", "", "", "", &PathError{p.key, fmt.Sprintf("The %s has no letters or digits that can make a web address.", p.key)}
		}
	}
	return flavor, region, realm, name, nil
}
