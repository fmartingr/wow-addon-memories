package export

import (
	"encoding/json"
	"sort"

	"github.com/fmartingr/wow-addon-memories/internal/journal"
)

// derived keys are computed again on each run, so they do not make two records different.
var derived = map[string]bool{"session": true, "screenshot": true, "notes": true}

func recordKey(r journal.Record) string {
	m := make(map[string]any, len(r))
	for k, v := range r {
		if !derived[k] {
			m[k] = v
		}
	}
	// A record holds only values that came from JSON or from the decoder, so it always marshals.
	b, _ := json.Marshal(m)
	return string(b)
}

func notesOf(v any) []Note {
	var out []Note
	switch list := v.(type) {
	case []Note:
		out = append(out, list...)
	case []any:
		for _, n := range list {
			switch n := n.(type) {
			case Note:
				out = append(out, n)
			case map[string]any:
				source, _ := n["source"].(string)
				note, _ := n["note"].(string)
				out = append(out, Note{Source: source, Note: note})
			}
		}
	}
	return out
}

// MergeRecords returns the multiset union of the records of an earlier run and of this run, sorted by time. A record
// of this run takes the screenshot and notes of its earlier copy when it has none of its own, so a screenshot that is
// gone from the Screenshots folder stays linked. An sn record of this run that JoinNotes left alone, such as after a
// later ss made a tie, is dropped when an earlier copy already carries its note on an ss within NoteTolerance.
func MergeRecords(old, fresh []journal.Record) []journal.Record {
	queue := map[string][]journal.Record{}
	var order []string
	for _, r := range old {
		k := recordKey(r)
		if _, ok := queue[k]; !ok {
			order = append(order, k)
		}
		queue[k] = append(queue[k], r)
	}
	carried := map[Note][]int64{}
	for _, r := range fresh {
		k := recordKey(r)
		if q := queue[k]; len(q) > 0 {
			for _, key := range []string{"screenshot", "notes"} {
				if _, ok := r[key]; !ok && q[0][key] != nil {
					r[key] = q[0][key]
					if key == "notes" {
						for _, n := range notesOf(r[key]) {
							carried[n] = append(carried[n], r.T())
						}
					}
				}
			}
			queue[k] = q[1:]
		}
	}
	out := make([]journal.Record, 0, len(fresh)+len(old))
	for _, r := range fresh {
		if r.String("k") == "sn" && takeCarried(carried, Note{Source: r.String("source"), Note: r.String("note")}, r.T()) {
			continue
		}
		out = append(out, r)
	}
	for _, k := range order {
		out = append(out, queue[k]...)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].T() < out[j].T() })
	return out
}

func takeCarried(carried map[Note][]int64, n Note, t int64) bool {
	times := carried[n]
	for i, at := range times {
		if absDiff(at, t) <= NoteTolerance {
			carried[n] = append(times[:i:i], times[i+1:]...)
			return true
		}
	}
	return false
}

func chunkKey(c journal.Chunk) [3]int64 {
	var s int64 = -1
	if c.S != nil {
		s = *c.S
	}
	return [3]int64{s, c.T, c.M}
}

// MergeTrail joins the trail chunks of two runs. A stretch grows while it is open, so chunks with the same session,
// start and map are one chunk, and the one with more points wins.
func MergeTrail(old, fresh []journal.Chunk) []journal.Chunk {
	best := map[[3]int64]journal.Chunk{}
	for _, c := range append(append([]journal.Chunk(nil), old...), fresh...) {
		k := chunkKey(c)
		if b, ok := best[k]; !ok || c.N >= b.N {
			best[k] = c
		}
	}
	out := make([]journal.Chunk, 0, len(best))
	for _, c := range best {
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := chunkKey(out[i]), chunkKey(out[j])
		if a[1] != b[1] {
			return a[1] < b[1]
		}
		if a[0] != b[0] {
			return a[0] < b[0]
		}
		return a[2] < b[2]
	})
	return out
}

type sessionKey struct {
	computer string
	start    int64
}

func keyOf(s map[string]any) (sessionKey, bool) {
	start, ok := journal.Int(s["start"])
	computer, _ := s["computer"].(string)
	return sessionKey{computer, start}, ok
}

func lastOf(s map[string]any) int64 {
	if last, ok := journal.Int(s["last"]); ok {
		return last
	}
	start, _ := journal.Int(s["start"])
	return start
}

// MergeSessions joins session lists. Sessions with the same computer and start are one session; the one that ran
// longest wins, and a later list wins a tie.
func MergeSessions(lists ...[]any) []map[string]any {
	best := map[sessionKey]map[string]any{}
	for _, list := range lists {
		for _, v := range list {
			s, ok := v.(map[string]any)
			if !ok {
				continue
			}
			k, ok := keyOf(s)
			if !ok {
				continue
			}
			if b, seen := best[k]; !seen || lastOf(s) >= lastOf(b) {
				best[k] = s
			}
		}
	}
	out := make([]map[string]any, 0, len(best))
	for _, s := range best {
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool {
		a, _ := keyOf(out[i])
		b, _ := keyOf(out[j])
		if a.start != b.start {
			return a.start < b.start
		}
		return a.computer < b.computer
	})
	return out
}

// SessionAt returns the 1-based index of the session that contains t, or 0. Sessions of two computers can overlap; the
// one that started last wins. It also returns the UTC offset of that session, else of the latest session that started
// at or before t, which names the screenshot files of that time. sessions are sorted by start, as MergeSessions returns
// them.
func SessionAt(sessions []map[string]any, t int64) (index int, tz int64, hasTZ bool) {
	found := false
	after := sort.Search(len(sessions), func(i int) bool {
		k, _ := keyOf(sessions[i])
		return k.start > t
	})
	for i := after - 1; i >= 0; i-- {
		if t <= lastOf(sessions[i]) {
			tz, hasTZ = journal.Int(sessions[i]["tz"])
			return i + 1, tz, hasTZ
		}
		if !found {
			found = true
			tz, hasTZ = journal.Int(sessions[i]["tz"])
		}
	}
	return 0, tz, hasTZ
}
