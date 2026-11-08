package validate

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

// MaxProblems is the most problems that a rejected upload reports.
const MaxProblems = 20

// maxField is the most bytes of Problem.Field. A field names keys of the upload, so a long key must not come back
// whole in a response or a log.
const maxField = 256

// The values of Problem.Code. Only too_large needs another status than the others.
const (
	CodeInvalid  = "invalid"
	CodeTooLarge = "too_large"
)

const (
	fileCharacter = "character"
	fileJourney   = "journey"
	fileTrail     = "trail"
)

// Problem is one reason to reject an upload. File is character, journey or trail, or empty when the problem
// concerns the whole upload. Line is the 1-based record or chunk number, or 0. Reason is plain English.
type Problem struct {
	File   string `json:"file"`
	Line   int    `json:"line"`
	Field  string `json:"field"`
	Reason string `json:"reason"`
	Code   string `json:"-"`
}

// TooLarge reports whether the upload went over the size limit, which the API answers with 413 and not 422.
func TooLarge(problems []Problem) bool {
	for _, p := range problems {
		if p.Code == CodeTooLarge {
			return true
		}
	}
	return false
}

// collector keeps the first MaxProblems problems. seen counts every problem, kept or not, so a check can tell
// that its value failed even when the list is full.
type collector struct {
	list []Problem
	seen int
}

func (c *collector) full() bool { return len(c.list) >= MaxProblems }

func (c *collector) add(p Problem) {
	c.seen++
	if !c.full() {
		p.Field = shortField(p.Field)
		c.list = append(c.list, p)
	}
}

// shortField cuts a field name to maxField bytes at a character boundary and marks the cut with "…".
func shortField(s string) string {
	if len(s) <= maxField {
		return s
	}
	cut := maxField
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return strings.ToValidUTF8(s[:cut], "?") + "…"
}

// checker adds the problems of one file, and of one line of it.
type checker struct {
	lim  Limits
	col  *collector
	file string
	line int
}

func (ck *checker) fail(field, format string, args ...any) {
	ck.col.add(Problem{File: ck.file, Line: ck.line, Field: field, Reason: fmt.Sprintf(format, args...), Code: CodeInvalid})
}
