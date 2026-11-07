package journal

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Point is one trail point with an absolute time. It is written as [time, x, y, flags].
type Point struct {
	T     int64
	X     int64
	Y     int64
	Flags string
}

// MarshalJSON writes the point as an array.
func (p Point) MarshalJSON() ([]byte, error) {
	return json.Marshal([]any{p.T, p.X, p.Y, p.Flags})
}

// UnmarshalJSON reads the array form.
func (p *Point) UnmarshalJSON(b []byte) error {
	var raw []json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		return err
	}
	if len(raw) != 4 {
		return fmt.Errorf("a trail point has %d values, want 4", len(raw))
	}
	for i, dst := range []any{&p.T, &p.X, &p.Y, &p.Flags} {
		if err := json.Unmarshal(raw[i], dst); err != nil {
			return err
		}
	}
	return nil
}

// Chunk is one trail stretch: s is the start of its session, t the time of its first point, m its map.
type Chunk struct {
	S   *int64  `json:"s"`
	T   int64   `json:"t"`
	M   int64   `json:"m"`
	N   int     `json:"n"`
	Pts []Point `json:"pts"`
}

// ErrBadChunk is returned for a trail chunk that cannot be decoded.
var ErrBadChunk = errors.New("bad trail chunk")

var pointPattern = regexp.MustCompile(`^([0-9]+),([0-9]+),([0-9]+),?(.*)$`)

// DecodeChunk decodes a saved trail chunk { s, t, m, n, d, o }. Points without flags keep the flags before them.
func DecodeChunk(v any) (Chunk, error) {
	m, ok := v.(map[string]any)
	if !ok {
		return Chunk{}, ErrBadChunk
	}
	t, okT := Int(m["t"])
	mp, okM := Int(m["m"])
	d, okD := m["d"].(string)
	if !okT || !okM || !okD {
		return Chunk{}, ErrBadChunk
	}
	c := Chunk{T: t, M: mp, Pts: []Point{}}
	if s, ok := Int(m["s"]); ok {
		c.S = &s
	}
	flags := "-"
	if d != "" {
		for _, part := range strings.Split(d, ";") {
			g := pointPattern.FindStringSubmatch(part)
			if g == nil {
				return Chunk{}, fmt.Errorf("%w: point %q", ErrBadChunk, part)
			}
			sec, err1 := strconv.ParseInt(g[1], 10, 64)
			x, err2 := strconv.ParseInt(g[2], 10, 64)
			y, err3 := strconv.ParseInt(g[3], 10, 64)
			if err := errors.Join(err1, err2, err3); err != nil {
				return Chunk{}, fmt.Errorf("%w: %w", ErrBadChunk, err)
			}
			if g[4] != "" {
				flags = g[4]
			}
			c.Pts = append(c.Pts, Point{T: t + sec, X: x, Y: y, Flags: flags})
		}
	}
	c.N = len(c.Pts)
	return c, nil
}

// Trail decodes the chunks of a saved trail { v, chunks, open }. The open copy is a stretch whose logout step did not
// run, so it is kept too. It returns the chunks and the number of chunks it could not decode.
func Trail(v any) ([]Chunk, int) {
	m, ok := v.(map[string]any)
	if !ok {
		return nil, 0
	}
	raw := List(m["chunks"])
	if open, ok := m["open"].(map[string]any); ok {
		raw = append(raw, open)
	}
	var out []Chunk
	bad := 0
	for _, r := range raw {
		c, err := DecodeChunk(r)
		if err != nil {
			bad++
			continue
		}
		out = append(out, c)
	}
	return out, bad
}
