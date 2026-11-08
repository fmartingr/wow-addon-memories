package merge

import (
	"maps"
	"slices"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

// coreAddon is listed first among the addons of an entry, the others follow in byte order.
const coreAddon = "Memories"

// Entry returns the index entry of a character, with the fields and the key order of the gather's index.json, and
// the file paths of the character page: path is ".", and each file is next to entry.json.
func Entry(id string, u *validate.Upload) jsonw.Ordered {
	var trailPoints, screenshots int
	for _, c := range u.Chunks {
		trailPoints += c.N
	}
	for _, r := range u.Records {
		if textOf(r, "screenshot") != "" {
			screenshots++
		}
	}
	var start, end any
	if n := len(u.Records); n > 0 {
		start, end = timeOf(u.Records[0]), timeOf(u.Records[n-1])
	}
	addons := []any{}
	names, _ := u.Character["addons"].(map[string]any)
	if _, ok := names[coreAddon]; ok {
		addons = append(addons, coreAddon)
	}
	for _, n := range slices.Sorted(maps.Keys(names)) {
		if n != coreAddon {
			addons = append(addons, n)
		}
	}
	ch := u.Character
	return jsonw.Ordered{
		{Key: "id", Value: id},
		{Key: "guid", Value: ch["guid"]},
		{Key: "name", Value: ch["name"]},
		{Key: "region", Value: ch["region"]},
		{Key: "realm", Value: ch["realm"]},
		{Key: "flavor", Value: ch["flavor"]},
		{Key: "class", Value: ch["class"]},
		{Key: "race", Value: ch["race"]},
		{Key: "sex", Value: ch["sex"]},
		{Key: "faction", Value: ch["faction"]},
		{Key: "level", Value: ch["level"]},
		{Key: "path", Value: "."},
		{Key: "journey", Value: "journey.jsonl"},
		{Key: "trail", Value: "trail.jsonl"},
		{Key: "character", Value: "character.json"},
		{Key: "steps", Value: len(u.Records)},
		{Key: "sessions", Value: len(sessionsOf(ch))},
		{Key: "trailPoints", Value: trailPoints},
		{Key: "screenshots", Value: screenshots},
		{Key: "addons", Value: addons},
		{Key: "start", Value: start},
		{Key: "end", Value: end},
	}
}
