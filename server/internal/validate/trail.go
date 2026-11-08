package validate

import (
	"fmt"
	"regexp"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
)

// A point has the flags of the addon (t f m g d w c i, joined), or "-" when none is on.
var flagsPattern = regexp.MustCompile(`^(-|[a-z]{0,8})$`)

// Point is one trail point with an absolute time.
type Point struct {
	T, X, Y int64
	Flags   string
}

// JSONValue writes the point as [time, x, y, flags].
func (p Point) JSONValue() any { return []any{p.T, p.X, p.Y, p.Flags} }

type points []Point

func (p points) Len() int     { return len(p) }
func (p points) At(i int) any { return p[i] }

// Chunk is one trail stretch: S is the start of its session, T the time of its first point, M its map and N the
// number of points.
type Chunk struct {
	S   *int64
	T   int64
	M   int64
	N   int
	Pts []Point
}

// JSONValue writes the keys in the order s, t, m, n, pts.
func (c Chunk) JSONValue() any {
	var s any
	if c.S != nil {
		s = *c.S
	}
	return jsonw.Ordered{{Key: "s", Value: s}, {Key: "t", Value: c.T}, {Key: "m", Value: c.M}, {Key: "n", Value: c.N}, {Key: "pts", Value: points(c.Pts)}}
}

// chunk checks one trail chunk. It returns false when the chunk is not usable.
func (ck *checker) chunk(v any) (Chunk, bool) {
	m, ok := v.(map[string]any)
	if !ok {
		ck.fail("", "Must be an object.")
		return Chunk{}, false
	}
	before := ck.col.seen
	for _, k := range sortedKeys(m) {
		switch k {
		case "s", "t", "m", "n", "pts":
		default:
			ck.fail(k, "Is not a part of a trail chunk.")
		}
	}
	for _, k := range []string{"s", "t", "m", "n", "pts"} {
		if _, ok := m[k]; !ok {
			ck.fail(k, "Is missing.")
		}
	}
	var c Chunk
	if v, ok := m["s"]; ok && v != nil {
		if s, ok := integer(v); ok {
			c.S = &s
		} else {
			ck.fail("s", "Must be a whole number or null.")
		}
	}
	if v, ok := m["t"]; ok {
		if t, ok := integer(v); ok {
			c.T = t
		} else {
			ck.fail("t", "Must be a whole number.")
		}
	}
	if v, ok := m["m"]; ok {
		ck.integer("m", v, 0, 100_000)
		c.M, _ = integer(v)
	}
	var n int64
	var nOK bool
	if v, ok := m["n"]; ok {
		ck.integer("n", v, 0, ck.lim.MaxPoints)
		n, nOK = integer(v)
		c.N = int(n)
	}
	list, ok := m["pts"].([]any)
	if !ok {
		ck.fail("pts", "Must be a list of points.")
		return c, false
	}
	if nOK && int64(len(list)) != n {
		ck.fail("pts", "Has %d points, but n says %d.", len(list), n)
		return c, false
	}
	c.Pts = make([]Point, 0, len(list))
	var prev int64
	for i, e := range list {
		if ck.col.full() {
			break
		}
		p, ok := ck.point(i, e)
		if !ok {
			continue
		}
		if p.T < prev {
			ck.fail(fmt.Sprintf("pts[%d]", i), "Is earlier than the point before it. Points must be in time order.")
		}
		prev = p.T
		c.Pts = append(c.Pts, p)
	}
	return c, ck.col.seen == before
}

// point checks one point. The field name is only built for a problem, because a trail has millions of points.
func (ck *checker) point(i int, v any) (Point, bool) {
	fail := func(sub, reason string) { ck.fail(fmt.Sprintf("pts[%d]%s", i, sub), "%s", reason) }
	a, ok := v.([]any)
	if !ok || len(a) != 4 {
		fail("", "Must be a list of 4 values: time, x, y and flags.")
		return Point{}, false
	}
	before := ck.col.seen
	var p Point
	var ok1, ok2, ok3 bool
	p.T, ok1 = integer(a[0])
	p.X, ok2 = integer(a[1])
	p.Y, ok3 = integer(a[2])
	if !ok1 || p.T < 0 {
		fail("[0]", "Must be a whole number of seconds, 0 or more.")
	}
	if !ok2 || p.X < 0 || p.X > 10_000 {
		fail("[1]", "Must be a whole number from 0 to 10000.")
	}
	if !ok3 || p.Y < 0 || p.Y > 10_000 {
		fail("[2]", "Must be a whole number from 0 to 10000.")
	}
	if s, ok := a[3].(string); !ok || !flagsPattern.MatchString(s) {
		fail("[3]", "Must be text of up to 8 lower-case letters, or -.")
	} else {
		p.Flags = s
	}
	return p, ck.col.seen == before
}
