// Package merge joins the data a server stores with a new upload. It is the Go port of mergeRecords, mergeTrail,
// mergeSessions and sessionAt of packages/memories_core/lib/src/gather/merge.dart, and the testdata/merge fixture
// holds both ports to the same bytes.
package merge

import (
	"cmp"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

// noteTolerance is the widest time gap between an sn record and the ss record whose note it repeats.
const noteTolerance = 2

// derived keys are computed again on each run, so they do not make two records different.
var derived = map[string]bool{"session": true, "screenshot": true, "notes": true}

// recordKey is the canonical JSON of the record without its derived keys.
func recordKey(r validate.Record) string {
	m := make(map[string]any, len(r))
	for k, v := range r {
		if !derived[k] {
			m[k] = v
		}
	}
	b, err := jsonw.Marshal(m, false)
	if err != nil {
		// A checked record always marshals. A record that does not is still told apart by its printed form.
		return fmt.Sprintf("%#v", m)
	}
	return string(b)
}

type note struct{ source, note string }

// notesOf reads the notes of a record in the forms that the validator and a decoded file give.
func notesOf(v any) []note {
	list, ok := v.([]any)
	if !ok {
		return nil
	}
	var out []note
	for _, e := range list {
		var n note
		switch e := e.(type) {
		case jsonw.Ordered:
			for _, p := range e {
				s, _ := p.Value.(string)
				switch p.Key {
				case "source":
					n.source = s
				case "note":
					n.note = s
				}
			}
		case map[string]any:
			n.source, _ = e["source"].(string)
			n.note, _ = e["note"].(string)
		default:
			continue
		}
		out = append(out, n)
	}
	return out
}

// intOf reads a whole json.Number, the form the validator gives every number.
func intOf(v any) (int64, bool) {
	n, ok := v.(json.Number)
	if !ok {
		return 0, false
	}
	i, err := strconv.ParseInt(string(n), 10, 64)
	return i, err == nil
}

// timeOf is the time of a record, or 0 when it has none.
func timeOf(r validate.Record) int64 {
	t, _ := intOf(r["t"])
	return t
}

func textOf(r validate.Record, key string) string {
	s, _ := r[key].(string)
	return s
}

// mergeRecords returns the multiset union of the records of the stored data and of an upload, sorted by time. A
// record of the upload takes the screenshot and notes of its stored copy when it has none of its own, so a
// screenshot that the upload no longer names stays linked. An sn record of the upload is dropped when its stored
// copy already carries its note on an ss within noteTolerance. It changes the records of fresh.
func mergeRecords(old, fresh []validate.Record) []validate.Record {
	queue := map[string][]validate.Record{}
	var order []string
	for _, r := range old {
		k := recordKey(r)
		if _, ok := queue[k]; !ok {
			order = append(order, k)
		}
		queue[k] = append(queue[k], r)
	}
	carried := carriedNotes{}
	for _, r := range fresh {
		k := recordKey(r)
		q := queue[k]
		if len(q) == 0 {
			continue
		}
		for _, key := range [...]string{"screenshot", "notes"} {
			if _, has := r[key]; has || q[0][key] == nil {
				continue
			}
			r[key] = q[0][key]
			if key == "notes" {
				for _, n := range notesOf(r[key]) {
					carried.add(n, timeOf(r))
				}
			}
		}
		queue[k] = q[1:]
	}
	out := make([]validate.Record, 0, len(fresh)+len(old))
	for _, r := range fresh {
		if textOf(r, "k") == "sn" && carried.take(note{textOf(r, "source"), textOf(r, "note")}, timeOf(r)) {
			continue
		}
		out = append(out, r)
	}
	for _, k := range order {
		out = append(out, queue[k]...)
	}
	slices.SortStableFunc(out, func(a, b validate.Record) int { return cmp.Compare(timeOf(a), timeOf(b)) })
	return out
}

// carriedNotes holds the times of the notes carried onto fresh records, by note and time, each time with the carry
// order of its notes. _takeCarried in merge.dart scans every carried time of a note for each sn; an upload with many
// copies of one note would make that sn records × notes on the server, so take looks only at the times within
// noteTolerance.
type carriedNotes struct {
	times map[note]map[int64][]int
	seq   int
}

func (c *carriedNotes) add(n note, t int64) {
	if c.times == nil {
		c.times = map[note]map[int64][]int{}
	}
	if c.times[n] == nil {
		c.times[n] = map[int64][]int{}
	}
	c.times[n][t] = append(c.times[n][t], c.seq)
	c.seq++
}

// take removes the carried note n within noteTolerance of t that was carried first, as the scan of merge.dart does,
// and reports whether there was one.
func (c *carriedNotes) take(n note, t int64) bool {
	byTime := c.times[n]
	best, first := int64(0), -1
	for at := t - noteTolerance; at <= t+noteTolerance; at++ {
		if q := byTime[at]; len(q) > 0 && (first < 0 || q[0] < first) {
			best, first = at, q[0]
		}
	}
	if first < 0 {
		return false
	}
	byTime[best] = byTime[best][1:]
	return true
}
