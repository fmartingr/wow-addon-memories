// Package openreg decides whether a new key can register without an invite. The admin turns open registration on and
// off, and the gate turns it off by itself when the data disk runs low on free space.
package openreg

import (
	"context"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// Gate reads the settings and the free space of the data folder in the background, so a request reads only memory.
type Gate struct {
	cur   atomic.Pointer[Status]
	store *store.Store
	dir   string
	log   *slog.Logger
	// freePercent returns the free space of the disk of dir, in percent, and false when the system cannot tell it.
	freePercent func(dir string) (float64, bool)
}

// New returns the gate of the data folder dir.
func New(st *store.Store, dir string, log *slog.Logger) *Gate {
	return &Gate{store: st, dir: dir, log: log, freePercent: freePercent}
}

// SetDiskProbe replaces the free space check, for tests.
func (g *Gate) SetDiskProbe(probe func(dir string) (float64, bool)) { g.freePercent = probe }

// Status is the state of open registration.
type Status struct {
	Settings store.OpenSettings
	// FreePercent is the free space of the data disk. FreeKnown is false when the system cannot tell it, and then
	// the disk never closes open registration.
	FreePercent float64
	FreeKnown   bool
}

// Open tells whether a new key can register without an invite now.
func (s Status) Open() bool { return s.Settings.Open && !s.Low() }

// Low tells whether the free space is at the limit of the settings or below it.
func (s Status) Low() bool { return s.FreeKnown && s.FreePercent <= float64(s.Settings.MinFreePercent) }

// Disk returns the free space of the data disk, and false when the system cannot tell it.
func (g *Gate) Disk() (float64, bool) { return g.freePercent(g.dir) }

// Refresh reads the settings and the free space, and keeps the result for Current. When open registration is on and
// the free space is low, it turns open registration off in the store, so it stays off until the admin turns it on
// again. On an error, Current keeps the last result.
func (g *Gate) Refresh(ctx context.Context) (Status, error) {
	o, err := g.store.OpenSettings(ctx)
	if err != nil {
		return Status{}, err
	}
	st := Status{Settings: o}
	st.FreePercent, st.FreeKnown = g.freePercent(g.dir)
	if o.Open && st.Low() {
		closed, err := g.store.CloseOpen(ctx)
		if err != nil {
			return Status{}, err
		}
		st.Settings.Open = false
		if closed {
			g.log.Warn("open registration is now closed because the data disk is low on free space. Registered keys keep working. Free some space, then turn open registration on in the admin page",
				"free_percent", st.FreePercent, "min_free_percent", o.MinFreePercent)
		}
	}
	g.cur.Store(&st)
	return st, nil
}

// Current returns the result of the last Refresh. Before the first Refresh, open registration is closed.
func (g *Gate) Current() Status {
	if st := g.cur.Load(); st != nil {
		return *st
	}
	return Status{Settings: store.DefaultOpenSettings()}
}

// IsOpen tells whether a new key can register without an invite, as the last Refresh saw it.
func (g *Gate) IsOpen() bool { return g.Current().Open() }

// Loop calls Refresh every interval until ctx ends. A failed Refresh is logged and keeps the last result.
func (g *Gate) Loop(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if _, err := g.Refresh(ctx); err != nil && ctx.Err() == nil {
				g.log.Error("could not read the open registration state", "err", err.Error())
			}
		}
	}
}
