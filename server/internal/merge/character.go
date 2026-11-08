package merge

import (
	"encoding/json"
	"maps"
	"strconv"

	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

func cloneRecords(rs []validate.Record) []validate.Record {
	out := make([]validate.Record, len(rs))
	for i, r := range rs {
		out[i] = maps.Clone(r)
	}
	return out
}

// Character merges an upload into the stored data of its character and returns the data to store. old is nil for
// a first upload. fresh and old stay as they are. With keepShots false, the records of fresh lose their screenshot
// field before the merge, so only a screenshot that old already holds stays linked.
func Character(old, fresh *validate.Upload, keepShots bool) *validate.Upload {
	if old == nil {
		old = &validate.Upload{}
	}
	freshRecords := cloneRecords(fresh.Records)
	if !keepShots {
		for _, r := range freshRecords {
			delete(r, "screenshot")
		}
	}
	records := mergeRecords(cloneRecords(old.Records), freshRecords)
	sessions := mergeSessions(sessionsOf(old.Character), sessionsOf(fresh.Character))
	index := newSessionIndex(sessions)
	for _, r := range records {
		if i := index.at(timeOf(r)); i > 0 {
			r["session"] = json.Number(strconv.Itoa(i))
		} else {
			r["session"] = nil
		}
	}

	doc := maps.Clone(fresh.Character)
	if doc == nil {
		doc = map[string]any{}
	}
	list := make([]any, len(sessions))
	for i, s := range sessions {
		list[i] = s
	}
	doc["sessions"] = list
	addons := map[string]any{}
	oldAddons, _ := old.Character["addons"].(map[string]any)
	freshAddons, _ := fresh.Character["addons"].(map[string]any)
	maps.Copy(addons, oldAddons)
	maps.Copy(addons, freshAddons)
	doc["addons"] = addons

	return &validate.Upload{
		Character: doc,
		Records:   records,
		Chunks:    mergeTrail(old.Chunks, fresh.Chunks),
		Flavor:    fresh.Flavor,
		Region:    fresh.Region,
		Realm:     fresh.Realm,
		Name:      fresh.Name,
	}
}

func sessionsOf(character map[string]any) []any {
	list, _ := character["sessions"].([]any)
	return list
}
