package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "usage: memories-export --wow-dir <flavor dir> [--dist DIR] [--backup DIR] [--default ID]")
	os.Exit(2)
}
