package kinds

import (
	"bytes"
	"os"
	"testing"
)

func TestCatalogMatchesDocs(t *testing.T) {
	f, err := os.Open("../../../docs/kinds.md")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	parsed, err := Parse(f)
	if err != nil {
		t.Fatal(err)
	}
	want, err := Marshal(parsed)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(want, catalogJSON) {
		t.Fatal("kinds.json does not match docs/kinds.md: run go generate ./internal/kinds")
	}
}
