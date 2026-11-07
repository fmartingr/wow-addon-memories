// Command memories-export turns the Memories saved files of a WoW flavor folder into the dist-characters layout.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/fmartingr/wow-addon-memories/internal/export"
)

const usage = "usage: memories-export --wow-dir <flavor dir> [--dist DIR] [--backup DIR] [--default ID]"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("memories-export", flag.ContinueOnError)
	fs.SetOutput(stderr)
	wowDir := fs.String("wow-dir", "", "WoW flavor folder, for example .../World of Warcraft/_forever_ (required)")
	dist := fs.String("dist", "./dist-characters", "output folder")
	backup := fs.String("backup", "./backups", "folder for the timestamped copies of the saved files and screenshots")
	def := fs.String("default", "", "id of the character the website opens first (default: the earlier choice, else the one played last)")
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if *wowDir == "" || *dist == "" || *backup == "" || fs.NArg() > 0 {
		_, _ = fmt.Fprintln(stderr, usage)
		return 2
	}
	err := export.Run(export.Options{
		WowDir: *wowDir, Dist: *dist, Backup: *backup, Default: *def, Now: time.Now(), Out: stdout,
	})
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "memories-export:", err)
		if errors.Is(err, export.ErrUsage) {
			return 2
		}
		return 1
	}
	return 0
}
