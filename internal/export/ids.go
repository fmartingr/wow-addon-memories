package export

import (
	"regexp"
	"slices"
	"strconv"
	"strings"

	"golang.org/x/text/unicode/norm"
)

var (
	nonSlug       = regexp.MustCompile(`[^a-z0-9]+`)
	portalPattern = regexp.MustCompile(`SET portal "(\w+)"`)
	// IDPattern is the form of every character id, so an id is always safe as a folder name.
	IDPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
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

// Region reads the region from the text of WTF/Config.wtf, or "xx" when it has none.
func Region(config string) string {
	if m := portalPattern.FindStringSubmatch(config); m != nil && Slug(m[1]) != "" {
		return Slug(m[1])
	}
	return "xx"
}

// BaseID is "<region>-<realm slug>-<name slug>", or "<region>-<guid slug>" when the name has no slug.
func BaseID(region, realm, name, guid string) string {
	if Slug(name) == "" {
		return joinNonEmpty(region, Slug(guid))
	}
	return joinNonEmpty(region, Slug(realm), Slug(name))
}

func joinNonEmpty(parts ...string) string {
	var keep []string
	for _, p := range parts {
		if p != "" {
			keep = append(keep, p)
		}
	}
	return strings.Join(keep, "-")
}

// candidates are the ids that AssignID tries first, in order. After them it tries the GUID id with a number from 2.
func candidates(base, flavor, guid string) (withGUID string, ids []string) {
	withGUID = joinNonEmpty(base, Slug(guid))
	return withGUID, []string{base, joinNonEmpty(base, Slug(flavor)), withGUID}
}

// isCandidate reports whether AssignID could give id to a character with this base id, flavor and GUID.
func isCandidate(id, base, flavor, guid string) bool {
	withGUID, ids := candidates(base, flavor, guid)
	if slices.Contains(ids, id) {
		return true
	}
	n, ok := strings.CutPrefix(id, withGUID+"-")
	if !ok {
		return false
	}
	i, err := strconv.Atoi(n)
	return err == nil && i >= 2 && strconv.Itoa(i) == n
}

// AssignID gives a character its id: the base id, else the base id with the flavor, else with the GUID. taken maps
// each id given so far to its GUID. Two GUIDs with the same slug get a number after the GUID.
func AssignID(taken map[string]string, base, flavor, guid string) string {
	withGUID, ids := candidates(base, flavor, guid)
	for n := 2; ; n++ {
		for _, c := range ids {
			if owner, ok := taken[c]; !ok || owner == guid {
				taken[c] = guid
				return c
			}
		}
		ids = []string{withGUID + "-" + strconv.Itoa(n)}
	}
}
