package validate

import (
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Limits are the size limits of one upload. Every field must be set; the server takes them from its config.
type Limits struct {
	// MaxDecodedBytes is the most JSON bytes after gzip is undone.
	MaxDecodedBytes int64
	// MaxText is the most bytes of one text value.
	MaxText int64
	// MaxRecords is the most journey records.
	MaxRecords int64
	// MaxChunks is the most trail chunks.
	MaxChunks int64
	// MaxPoints is the most points in one trail chunk.
	MaxPoints int64
}

const (
	maxDepth        = 16
	maxNumberLength = 32
	maxRecordKeys   = 48
	maxCharKeys     = 64
	maxSessions     = 100_000
	maxAddons       = 32
	maxTreeValues   = 20_000
	maxTreeDepth    = 4
	maxTreeKey      = 128  // item and profession names make the keys of counts
	maxTreeText     = 4096 // the skills snapshot of a character with many professions is 536 bytes at level 10
	maxNotes        = 16
	minTime         = 1104537600 // 2005-01-01 UTC, before the first WoW addon could write a record
	timeSlack       = 86400

	// The token budgets of one value sit above the most that the checks allow: 16 tokens for each session, at most 3
	// for each value of the addon trees, and 2 for each of the at most 999 extra fields of a record.
	characterTokens = maxSessions*16 + maxTreeValues*4 + 4096
	recordTokens    = 4096
)

// chunkTokens is the token budget of one trail chunk: 6 tokens for each point and its brackets.
func chunkTokens(maxPoints int64) int64 { return maxPoints*6 + 64 }

// integer reads a JSON number written as a whole number, with no fraction or exponent.
func integer(v any) (int64, bool) {
	n, ok := v.(json.Number)
	if !ok {
		return 0, false
	}
	i, err := strconv.ParseInt(string(n), 10, 64)
	return i, err == nil
}

// number reads a finite JSON number of a sane length.
func number(v any) (float64, bool) {
	n, ok := v.(json.Number)
	if !ok || len(n) > maxNumberLength {
		return 0, false
	}
	f, err := strconv.ParseFloat(string(n), 64)
	return f, err == nil && !math.IsInf(f, 0) && !math.IsNaN(f)
}

// intReason returns why v is not a whole number from lo to hi, or "" when it is.
func intReason(v any, lo, hi int64) string {
	i, ok := integer(v)
	if !ok || i < lo || i > hi {
		return fmt.Sprintf("Must be a whole number from %d to %d.", lo, hi)
	}
	return ""
}

// numberReason returns why v is not a finite number from lo to hi, or "" when it is.
func numberReason(v any, lo, hi float64) string {
	f, ok := number(v)
	if !ok {
		return "Must be a finite number."
	}
	if f < lo || f > hi {
		return fmt.Sprintf("Must be a number from %g to %g.", lo, hi)
	}
	return ""
}

// textReason returns why v is not text of min to max bytes, or "" when it is. A max of 0, or more than MaxText,
// means MaxText. Text has no control character and no "|", because the addon writes neither into its saved lines.
func (l Limits) textReason(v any, min, max int) string {
	if max == 0 || int64(max) > l.MaxText {
		max = int(l.MaxText)
	}
	return textReason(v, min, max, false)
}

// textReason is the text check. The counts and snap of an addon allow "|", because the addon does not replace it
// there, and have their own length limits.
func textReason(v any, min, max int, allowPipe bool) string {
	s, ok := v.(string)
	if !ok {
		return "Must be text."
	}
	switch {
	case !utf8.ValidString(s):
		return "Must be valid UTF-8 text."
	case len(s) < min && min == 1:
		return "Must not be empty."
	case len(s) < min:
		return fmt.Sprintf("Must have at least %d bytes.", min)
	case len(s) > max:
		return fmt.Sprintf("Must have at most %d bytes.", max)
	case strings.ContainsFunc(s, func(r rune) bool { return r < 0x20 || r == 0x7f }):
		return "Must not have control characters."
	case !allowPipe && strings.Contains(s, "|"):
		return `Must not have the character "|".`
	}
	return ""
}

func (ck *checker) text(field string, v any, min, max int) {
	if r := ck.lim.textReason(v, min, max); r != "" {
		ck.fail(field, "%s", r)
	}
}

func (ck *checker) integer(field string, v any, lo, hi int64) {
	if r := intReason(v, lo, hi); r != "" {
		ck.fail(field, "%s", r)
	}
}

func (ck *checker) number(field string, v any, lo, hi float64) {
	if r := numberReason(v, lo, hi); r != "" {
		ck.fail(field, "%s", r)
	}
}

// integerOrNull is for a field that may be null.
func (ck *checker) integerOrNull(field string, v any, lo, hi int64) {
	if v != nil {
		ck.integer(field, v, lo, hi)
	}
}

func (ck *checker) numberOrNull(field string, v any, lo, hi float64) {
	if v != nil {
		ck.number(field, v, lo, hi)
	}
}
