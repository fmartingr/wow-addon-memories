package kinds

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"regexp"
	"strings"
)

var (
	sectionRow = regexp.MustCompile("^## (Memories[A-Za-z_]*)\\s*$")
	kindRow    = regexp.MustCompile("^\\|\\s*`([a-z][a-z0-9]*)`\\s*\\|[^|]*\\|[^|]*\\|(.*)\\|\\s*$")
	fieldCell  = regexp.MustCompile("`(#?)([A-Za-z][A-Za-z0-9]*)`")
)

// Parse reads the kind tables of docs/kinds.md: one "## <Addon>" section per addon, and in it one row
// "| `kind` | Group | Name | `field`, `#number` |" per kind. A row outside such a section is not a kind.
func Parse(r io.Reader) (map[string]Kind, error) {
	out := map[string]Kind{}
	addon := ""
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for n := 1; sc.Scan(); n++ {
		line := sc.Text()
		if level := len(line) - len(strings.TrimLeft(line, "#")); level == 1 || level == 2 {
			addon = ""
			if m := sectionRow.FindStringSubmatch(line); m != nil {
				addon = m[1]
			}
			continue
		}
		m := kindRow.FindStringSubmatch(line)
		if addon == "" || m == nil {
			continue
		}
		if _, dup := out[m[1]]; dup {
			return nil, fmt.Errorf("line %d: the kind %q is listed twice", n, m[1])
		}
		k := Kind{Addon: addon, Fields: map[string]FieldType{}}
		cell := strings.TrimSpace(m[2])
		for _, f := range fieldCell.FindAllStringSubmatch(cell, -1) {
			if _, dup := k.Fields[f[2]]; dup {
				return nil, fmt.Errorf("line %d: the kind %q has the field %q twice", n, m[1], f[2])
			}
			k.Fields[f[2]] = Text
			if f[1] == "#" {
				k.Fields[f[2]] = Number
			}
		}
		if len(k.Fields) == 0 && cell != "—" {
			return nil, fmt.Errorf("line %d: the kind %q has no field and no \"—\"", n, m[1])
		}
		out[m[1]] = k
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no kind found: the file needs sections like \"## Memories\" with kind tables")
	}
	return out, nil
}

// Marshal writes the catalog as kinds.json: sorted keys, two-space indent, a newline at the end.
func Marshal(catalog map[string]Kind) ([]byte, error) {
	b, err := json.MarshalIndent(catalog, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}
