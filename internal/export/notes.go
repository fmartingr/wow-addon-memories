package export

import (
	"cmp"
	"slices"
	"sort"

	"github.com/fmartingr/wow-addon-memories/internal/journal"
)

// NoteTolerance is the widest time gap between an sn line and the ss line it joins by time.
const NoteTolerance = 2

// Note is a screenshot note from another addon.
type Note struct {
	Source string `json:"source"`
	Note   string `json:"note"`
}

// JoinNotes moves each sn record into the notes of its ss record and returns the records without the joined sn
// records. An sn joins the ss with the same file, else the nearest ss within NoteTolerance seconds that no other sn
// took. A tie or no match keeps the sn record.
func JoinNotes(records []journal.Record) (out []journal.Record, joined int) {
	var shots, notes []int
	for i, r := range records {
		switch r.String("k") {
		case "ss":
			shots = append(shots, i)
		case "sn":
			notes = append(notes, i)
		}
	}
	shotByFile := map[string]int{}
	for _, s := range shots {
		if file := records[s].String("file"); file != "" {
			if _, ok := shotByFile[file]; !ok {
				shotByFile[file] = s
			}
		}
	}
	target := map[int]int{}
	taken := map[int]bool{}
	for _, n := range notes {
		file := records[n].String("file")
		if s, ok := shotByFile[file]; ok && file != "" {
			target[n] = s
			taken[s] = true
		}
	}

	byTime := slices.Clone(shots)
	slices.SortStableFunc(byTime, func(a, b int) int { return cmp.Compare(records[a].T(), records[b].T()) })
	var pairs []pair
	for _, n := range notes {
		if _, ok := target[n]; ok {
			continue
		}
		t := records[n].T()
		from := sort.Search(len(byTime), func(i int) bool { return records[byTime[i]].T() >= t-NoteTolerance })
		var near []int
		for _, s := range byTime[from:] {
			if records[s].T() > t+NoteTolerance {
				break
			}
			near = append(near, s)
		}
		// The record order keeps the stable sort in matchNearest deterministic.
		sort.Ints(near)
		for _, s := range near {
			if taken[s] || records[s].String("result") == "failed" {
				continue
			}
			pairs = append(pairs, pair{n, s, absDiff(t, records[s].T())})
		}
	}
	matchNearest(pairs, func(s int) bool { return !taken[s] }, func(n, s int) {
		target[n] = s
		taken[s] = true
	})

	attached := map[int][]Note{}
	for _, n := range notes {
		if s, ok := target[n]; ok {
			attached[s] = append(attached[s], Note{Source: records[n].String("source"), Note: records[n].String("note")})
		}
	}
	for i, r := range records {
		if _, ok := target[i]; ok {
			joined++
			continue
		}
		if ns, ok := attached[i]; ok {
			r["notes"] = ns
		}
		out = append(out, r)
	}
	return out, joined
}

func absDiff(a, b int64) int64 {
	if a > b {
		return a - b
	}
	return b - a
}
