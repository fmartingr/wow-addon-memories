//go:build !(linux || darwin || freebsd)

package openreg

func freePercent(string) (float64, bool) { return 0, false }
