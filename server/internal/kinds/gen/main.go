// Command gen makes kinds.json from docs/kinds.md: gen <kinds.md> <kinds.json>.
package main

import (
	"fmt"
	"os"

	"github.com/fmartingr/wow-addon-memories/server/internal/kinds"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: gen <kinds.md> <kinds.json>")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, "gen:", err)
		os.Exit(1)
	}
}

func run(src, dst string) error {
	f, err := os.Open(src)
	if err != nil {
		return err
	}
	defer f.Close()
	catalog, err := kinds.Parse(f)
	if err != nil {
		return fmt.Errorf("%s: %w", src, err)
	}
	b, err := kinds.Marshal(catalog)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, b, 0o644)
}
