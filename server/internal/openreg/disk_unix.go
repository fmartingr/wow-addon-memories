//go:build linux || darwin || freebsd

package openreg

import "syscall"

func freePercent(dir string) (float64, bool) {
	var fs syscall.Statfs_t
	if err := syscall.Statfs(dir, &fs); err != nil || fs.Blocks == 0 {
		return 0, false
	}
	// Bavail counts the blocks that an unprivileged process may use, which leaves out the blocks reserved for root.
	return float64(fs.Bavail) / float64(fs.Blocks) * 100, true
}
