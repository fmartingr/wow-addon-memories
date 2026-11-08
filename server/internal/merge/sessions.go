package merge

import (
	"cmp"
	"math"
	"slices"
	"sort"
)

type sessionKey struct {
	computer string
	start    int64
}

func keyOfSession(s map[string]any) (sessionKey, bool) {
	start, ok := intOf(s["start"])
	computer, _ := s["computer"].(string)
	return sessionKey{computer, start}, ok
}

// lastOf is the time a session was last seen, else its start.
func lastOf(s map[string]any) int64 {
	if last, ok := intOf(s["last"]); ok {
		return last
	}
	start, _ := intOf(s["start"])
	return start
}

// mergeSessions joins session lists. Sessions with the same computer and start are one session; the one that ran
// longest wins, and a later list wins a tie. Sessions that are not objects, or have no start, are dropped.
func mergeSessions(lists ...[]any) []map[string]any {
	best := map[sessionKey]map[string]any{}
	for _, list := range lists {
		for _, v := range list {
			s, ok := v.(map[string]any)
			if !ok {
				continue
			}
			k, ok := keyOfSession(s)
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
	slices.SortFunc(out, func(x, y map[string]any) int {
		a, _ := keyOfSession(x)
		b, _ := keyOfSession(y)
		return cmp.Or(cmp.Compare(a.start, b.start), cmp.Compare(a.computer, b.computer))
	})
	return out
}

// sessionIndex answers sessionAt for many times. The scan of sessionAt in merge.dart walks back through every
// earlier session for a time in no session; an upload with many sessions and records between them would make that
// records × sessions on the server, so a max tree of last finds the same session in O(log n).
type sessionIndex struct {
	starts  []int64
	size    int
	maxLast []int64
}

// newSessionIndex indexes sessions sorted by start, as mergeSessions returns them.
func newSessionIndex(sessions []map[string]any) *sessionIndex {
	size := 1
	for size < len(sessions) {
		size *= 2
	}
	x := &sessionIndex{starts: make([]int64, len(sessions)), size: size, maxLast: make([]int64, 2*size)}
	for i := range x.maxLast {
		x.maxLast[i] = math.MinInt64
	}
	for i, s := range sessions {
		k, _ := keyOfSession(s)
		x.starts[i] = k.start
		x.maxLast[size+i] = lastOf(s)
	}
	for i := size - 1; i > 0; i-- {
		x.maxLast[i] = max(x.maxLast[2*i], x.maxLast[2*i+1])
	}
	return x
}

// latest returns the largest index below end, within the node that covers [lo, hi), of a session last seen at or
// after t, or -1.
func (x *sessionIndex) latest(node, lo, hi, end int, t int64) int {
	if lo >= end || x.maxLast[node] < t {
		return -1
	}
	if hi-lo == 1 {
		return lo
	}
	mid := (lo + hi) / 2
	if i := x.latest(2*node+1, mid, hi, end, t); i >= 0 {
		return i
	}
	return x.latest(2*node, lo, mid, end, t)
}

// at returns the 1-based index of the session that contains t, or 0. Sessions of two computers can overlap; the one
// that started last wins.
func (x *sessionIndex) at(t int64) int {
	after := sort.Search(len(x.starts), func(i int) bool { return x.starts[i] > t })
	return x.latest(1, 0, x.size, after, t) + 1
}
