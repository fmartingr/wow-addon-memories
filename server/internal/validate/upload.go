// Package validate checks one upload of a character and returns it in the form that the server stores.
package validate

import (
	"compress/gzip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/ids"
	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
)

// Upload is a checked upload. Flavor, Region, Realm and Name are the segments of the web address of the character.
type Upload struct {
	Character map[string]any
	Records   []Record
	Chunks    []Chunk

	Flavor, Region, Realm, Name string
}

// CharacterJSON writes character.json as the server stores it.
func (u *Upload) CharacterJSON() ([]byte, error) { return jsonw.Marshal(u.Character, true) }

// JourneyJSONL writes journey.jsonl as the server stores it.
func (u *Upload) JourneyJSONL() ([]byte, error) {
	return jsonw.Lines(len(u.Records), func(i int) any { return u.Records[i] })
}

// TrailJSONL writes trail.jsonl as the server stores it.
func (u *Upload) TrailJSONL() ([]byte, error) {
	return jsonw.Lines(len(u.Chunks), func(i int) any { return u.Chunks[i] })
}

var (
	errTooLarge = errors.New("the upload is too large")
	errStop     = errors.New("enough problems")
)

// capReader fails with errTooLarge when more than left bytes come out of r.
type capReader struct {
	r    io.Reader
	left int64
}

func (c *capReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.left -= int64(n)
	if c.left < 0 {
		return 0, errTooLarge
	}
	return n, err
}

// bodyReader keeps the first error of the request body other than its end, so a body that went over the request
// limit of http.MaxBytesReader is reported as too large and not as damaged gzip data.
type bodyReader struct {
	r   io.Reader
	err error
}

func (b *bodyReader) Read(p []byte) (int, error) {
	n, err := b.r.Read(p)
	if err != nil && err != io.EOF && b.err == nil {
		b.err = err
	}
	return n, err
}

// bodyTooLarge returns the too_large problem when the request body went over its http.MaxBytesReader limit.
func bodyTooLarge(err error) ([]Problem, bool) {
	var mbe *http.MaxBytesError
	if !errors.As(err, &mbe) {
		return nil, false
	}
	return []Problem{{Reason: fmt.Sprintf("The upload has more than %d bytes.", mbe.Limit), Code: CodeTooLarge}}, true
}

// Read decodes and checks the gzip stream of one upload: a JSON object {character, journey, trail}. It returns the
// upload, or the problems, never both. It stops after MaxProblems problems. now is the clock for the time checks.
func Read(raw io.Reader, lim Limits, now time.Time) (*Upload, []Problem) {
	col := &collector{}
	body := &bodyReader{r: raw}
	gz, err := gzip.NewReader(body)
	if err != nil {
		if problems, ok := bodyTooLarge(body.err); ok {
			return nil, problems
		}
		col.add(Problem{Reason: "The upload is not a gzip file.", Code: CodeInvalid})
		return nil, col.list
	}
	defer gz.Close()
	dec := json.NewDecoder(&capReader{r: gz, left: lim.MaxDecodedBytes})
	dec.UseNumber()
	p := &parser{dec: dec, col: col, lim: lim, st: journalState{now: now.Unix()}}
	err = p.run()
	if problems, ok := bodyTooLarge(body.err); ok {
		return nil, problems
	}
	switch {
	case errors.Is(err, errTooLarge):
		return nil, []Problem{{Reason: fmt.Sprintf("The upload has more than %d bytes of data after it is unpacked.", lim.MaxDecodedBytes), Code: CodeTooLarge}}
	case err == nil || errors.Is(err, errStop):
	default:
		col.add(p.streamProblem(err))
	}
	if len(col.list) > 0 {
		return nil, col.list
	}
	return p.up, nil
}

type parser struct {
	dec     *json.Decoder
	col     *collector
	lim     Limits
	st      journalState
	up      *Upload
	section string
	line    int
	// left is what is left of the tokens of the value being read, so a crafted list of tiny values cannot take
	// many times its bytes in memory before the checks see it.
	left, budget int64
}

// begin sets the token budget of the next value.
func (p *parser) begin(budget int64) {
	p.left, p.budget = budget, budget
}

// token reads one token of a value and spends one of its budget.
func (p *parser) token() (json.Token, error) {
	p.left--
	if p.left < 0 {
		return nil, errValues
	}
	return p.dec.Token()
}

func (p *parser) here() *checker {
	return &checker{lim: p.lim, col: p.col, file: p.section, line: p.line}
}

func (p *parser) problem(field, format string, args ...any) {
	p.here().fail(field, format, args...)
}

// streamProblem turns a read or syntax error into a problem. The error text of the standard library is not shown.
func (p *parser) streamProblem(err error) Problem {
	var syntax *json.SyntaxError
	reason := "The upload ends too early, or the gzip data is damaged."
	switch {
	case errors.Is(err, errDepth):
		reason = fmt.Sprintf("The JSON has more than %d levels of objects and lists.", maxDepth)
	case errors.Is(err, errValues):
		reason = fmt.Sprintf("Has more than %d JSON values.", p.budget)
	case errors.As(err, &syntax):
		reason = fmt.Sprintf("The data is not valid JSON, near byte %d.", syntax.Offset)
	}
	return Problem{File: p.section, Line: p.line, Reason: reason, Code: CodeInvalid}
}

var (
	errDepth  = errors.New("the JSON is nested too deep")
	errValues = errors.New("the value has too many tokens")
)

func (p *parser) run() error {
	p.up = &Upload{}
	tok, err := p.dec.Token()
	if err != nil {
		return err
	}
	if d, ok := tok.(json.Delim); !ok || d != '{' {
		p.problem("", "The upload must be one JSON object with the keys character, journey and trail.")
		return errStop
	}
	seen := map[string]bool{}
	var character any
	for p.dec.More() {
		if p.col.full() {
			return errStop
		}
		p.section, p.line = "", 0
		ktok, err := p.dec.Token()
		if err != nil {
			return err
		}
		key, _ := ktok.(string)
		known := key == fileCharacter || key == fileJourney || key == fileTrail
		if seen[key] {
			p.problem(key, "Appears twice.")
		}
		if !known {
			p.problem(key, "Is not a part of an upload. An upload has the keys character, journey and trail.")
		}
		seen[key] = true
		p.section = key
		switch key {
		case fileCharacter:
			p.begin(characterTokens)
			v, err := p.value(2)
			if err != nil {
				return err
			}
			character = v
		case fileJourney, fileTrail:
			if err := p.list(key); err != nil {
				return err
			}
		default:
			p.section = ""
			p.begin(recordTokens)
			if _, err := p.value(2); err != nil {
				return err
			}
		}
	}
	if _, err := p.dec.Token(); err != nil {
		return err
	}
	p.section, p.line = "", 0
	if _, err := p.dec.Token(); !errors.Is(err, io.EOF) {
		var syntax *json.SyntaxError
		if err == nil || errors.As(err, &syntax) {
			p.problem("", "The upload has more data after the JSON object.")
			return errStop
		}
		return err
	}
	for _, k := range []string{fileCharacter, fileJourney, fileTrail} {
		if !seen[k] {
			p.section = k
			p.problem("", "The upload has no %s.", k)
		}
	}
	if seen[fileCharacter] {
		p.section = fileCharacter
		p.up.Character = p.here().character(character)
	}
	if p.up.Character != nil && len(p.col.list) == 0 {
		var perr *ids.PathError
		var err error
		p.up.Flavor, p.up.Region, p.up.Realm, p.up.Name, err = ids.Path(p.up.Character)
		if errors.As(err, &perr) {
			p.problem(perr.Field, "%s", perr.Reason)
		}
	}
	return nil
}

// list reads the journey records or the trail chunks one by one and checks each, so a rejected upload costs no
// more memory than its first problems.
func (p *parser) list(section string) error {
	tok, err := p.dec.Token()
	if err != nil {
		return err
	}
	if d, ok := tok.(json.Delim); !ok || d != '[' {
		p.problem("", "Must be a list.")
		p.begin(recordTokens)
		_, err := p.from(tok, 2)
		return err
	}
	limit, budget := p.lim.MaxRecords, int64(recordTokens)
	if section == fileTrail {
		limit, budget = p.lim.MaxChunks, chunkTokens(p.lim.MaxPoints)
	}
	for p.dec.More() {
		p.line++
		if int64(p.line) > limit {
			p.problem("", "Has more than %d entries.", limit)
			return errStop
		}
		p.begin(budget)
		v, err := p.value(3)
		if err != nil {
			return err
		}
		if p.col.full() {
			return errStop
		}
		ck := p.here()
		if section == fileJourney {
			if rec := ck.record(v, &p.st); rec != nil {
				p.up.Records = append(p.up.Records, rec)
			}
		} else if c, ok := ck.chunk(v); ok {
			p.up.Chunks = append(p.up.Chunks, c)
		}
	}
	_, err = p.dec.Token()
	return err
}

func (p *parser) value(depth int) (any, error) {
	tok, err := p.token()
	if err != nil {
		return nil, err
	}
	return p.from(tok, depth)
}

// from reads the rest of a value whose first token is tok. depth is the level of the value, with 1 for the top object.
func (p *parser) from(tok json.Token, depth int) (any, error) {
	d, ok := tok.(json.Delim)
	if !ok {
		return tok, nil
	}
	if depth > maxDepth {
		return nil, errDepth
	}
	if d == '[' {
		list := []any{}
		for p.dec.More() {
			v, err := p.value(depth + 1)
			if err != nil {
				return nil, err
			}
			list = append(list, v)
		}
		_, err := p.token()
		return list, err
	}
	obj := map[string]any{}
	for p.dec.More() {
		ktok, err := p.token()
		if err != nil {
			return nil, err
		}
		key, _ := ktok.(string)
		v, err := p.value(depth + 1)
		if err != nil {
			return nil, err
		}
		if _, dup := obj[key]; dup {
			p.problem(key, "The key appears twice in one object.")
		}
		obj[key] = v
	}
	_, err := p.token()
	return obj, err
}
