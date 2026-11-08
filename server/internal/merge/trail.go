package merge

import (
	"cmp"
	"slices"

	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

type chunkKey struct{ s, t, m int64 }

func keyOfChunk(c validate.Chunk) chunkKey {
	k := chunkKey{s: -1, t: c.T, m: c.M}
	if c.S != nil {
		k.s = *c.S
	}
	return k
}

// mergeTrail joins the trail chunks of two runs. A stretch grows while it is open, so chunks with the same session,
// start and map are one chunk, and the one with more points wins; the later list wins a tie.
func mergeTrail(old, fresh []validate.Chunk) []validate.Chunk {
	best := map[chunkKey]validate.Chunk{}
	for _, list := range [...][]validate.Chunk{old, fresh} {
		for _, c := range list {
			k := keyOfChunk(c)
			if b, ok := best[k]; !ok || c.N >= b.N {
				best[k] = c
			}
		}
	}
	out := make([]validate.Chunk, 0, len(best))
	for _, c := range best {
		out = append(out, c)
	}
	slices.SortFunc(out, func(x, y validate.Chunk) int {
		a, b := keyOfChunk(x), keyOfChunk(y)
		return cmp.Or(cmp.Compare(a.t, b.t), cmp.Compare(a.s, b.s), cmp.Compare(a.m, b.m))
	})
	return out
}
