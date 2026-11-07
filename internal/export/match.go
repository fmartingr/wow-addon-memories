package export

import (
	"regexp"
	"sort"
	"time"
)

// ShotTolerance is the widest gap in seconds between a record and the time in a screenshot file name.
const ShotTolerance = 2

// FileNamePattern is the only form of screenshot file name that the converter reads or copies.
var FileNamePattern = regexp.MustCompile(`^WoWScrnShot_\d{6}_\d{6}\.(jpg|png|tga)$`)

const fileTimeLayout = "010206_150405"

// Shot is a record that names a screenshot: its predicted file, its time, and the UTC offset of the client clock.
type Shot struct {
	File  string
	T     int64
	TZ    int64
	HasTZ bool
}

// FileTime returns the unix time of a screenshot file name. The name holds the client's local time, tz seconds ahead
// of UTC.
func FileTime(name string, tz int64) (int64, bool) {
	const prefix = len("WoWScrnShot_")
	if len(name) < prefix+len(fileTimeLayout) {
		return 0, false
	}
	t, err := time.ParseInLocation(fileTimeLayout, name[prefix:prefix+len(fileTimeLayout)], time.FixedZone("", int(tz)))
	if err != nil {
		return 0, false
	}
	return t.Unix(), true
}

// MatchShots returns, for each shot, the index of its file in files, or -1. A shot takes the file with its exact name
// first, else the nearest unclaimed file within ShotTolerance seconds. A tie matches nothing. claimed holds files that
// earlier runs gave to other records; MatchShots adds the files it gives.
func MatchShots(shots []Shot, files []string, claimed map[string]bool) []int {
	out := make([]int, len(shots))
	index := make(map[string]int, len(files))
	for i, f := range files {
		index[f] = i
	}
	for i, s := range shots {
		out[i] = -1
		if j, ok := index[s.File]; ok && !claimed[s.File] {
			claimed[s.File] = true
			out[i] = j
		}
	}

	utc := make([]int64, len(files))
	bySecond := map[int64][]int{}
	for j, f := range files {
		if t, ok := FileTime(f, 0); ok {
			utc[j] = t
			bySecond[t] = append(bySecond[t], j)
		}
	}
	var pairs []pair
	for i, s := range shots {
		if out[i] >= 0 || !s.HasTZ {
			continue
		}
		var near []int
		for d := int64(-ShotTolerance); d <= ShotTolerance; d++ {
			near = append(near, bySecond[s.T+s.TZ+d]...)
		}
		// The ascending file order keeps the stable sort in matchNearest deterministic.
		sort.Ints(near)
		for _, j := range near {
			if !claimed[files[j]] {
				pairs = append(pairs, pair{i, j, absDiff(utc[j]-s.TZ, s.T)})
			}
		}
	}
	matchNearest(pairs, func(j int) bool { return !claimed[files[j]] }, func(i, j int) {
		claimed[files[j]] = true
		out[i] = j
	})
	return out
}

// pair is a possible match of a to b at a distance.
type pair struct {
	a, b int
	dist int64
}

// matchNearest gives each a its nearest free b, nearest pairs first. An a with two free b at its nearest distance gets
// nothing. take must make b no longer free.
func matchNearest(pairs []pair, free func(b int) bool, take func(a, b int)) {
	sort.SliceStable(pairs, func(i, j int) bool { return pairs[i].dist < pairs[j].dist })
	byA := map[int][]pair{}
	for _, c := range pairs {
		byA[c.a] = append(byA[c.a], c)
	}
	done := map[int]bool{}
	for _, c := range pairs {
		if done[c.a] || !free(c.b) {
			continue
		}
		done[c.a] = true
		tie := false
		for _, o := range byA[c.a] {
			if o.b != c.b && o.dist == c.dist && free(o.b) {
				tie = true
				break
			}
		}
		if !tie {
			take(c.a, c.b)
		}
	}
}
