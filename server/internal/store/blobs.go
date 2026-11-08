package store

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// ErrBadPath means that a blob path has a part that the server never writes.
var ErrBadPath = errors.New("store: bad blob path")

// File is an open blob. *os.File satisfies it, so http.ServeContent can serve it.
type File interface {
	io.ReadSeekCloser
	Stat() (fs.FileInfo, error)
}

// Blobs holds the character files. A path is <claim id>/<file>, with the file in the fixed list of the character
// files or screenshots/<name>. A path outside that shape is an error, so that no caller can reach another folder.
type Blobs interface {
	// Write stores r at path through a temporary file and a rename, so a reader sees the old or the new file, never a partial one.
	Write(ctx context.Context, path string, r io.Reader) error
	// Open returns the file, or an error that matches fs.ErrNotExist.
	Open(ctx context.Context, path string) (File, error)
	// Remove deletes one file. A file that does not exist is not an error.
	Remove(ctx context.Context, path string) error
	// RemoveAll deletes a prefix such as "<claim id>/" and everything under it. A prefix that does not exist is not an error.
	RemoveAll(ctx context.Context, prefix string) error
	// Size returns the bytes of all files under the prefix. A prefix that does not exist has size 0.
	Size(ctx context.Context, prefix string) (int64, error)
}

var (
	claimDir       = regexp.MustCompile(`^[0-9]+$`)
	shotFile       = regexp.MustCompile(`^WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png)$`)
	characterFiles = map[string]bool{"character.json": true, "journey.jsonl": true, "trail.jsonl": true, "entry.json": true}
)

const (
	shotDir = "screenshots"
	// tmpPrefix marks the temporary file of a Write. Size skips it, so a write in progress or one cut short by a
	// crash does not count toward a quota.
	tmpPrefix = ".tmp-"
)

// DiskBlobs stores blobs below one folder of a local disk.
type DiskBlobs struct{ root string }

// NewDiskBlobs roots the blobs at <dataDir>/characters and creates that folder.
func NewDiskBlobs(dataDir string) (*DiskBlobs, error) {
	root := filepath.Join(dataDir, "characters")
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, fmt.Errorf("could not create the folder %s: %w", root, err)
	}
	return &DiskBlobs{root: root}, nil
}

// parts validates a blob path or prefix and returns its parts. The valid shapes are <id>, <id>/<character file>,
// <id>/screenshots and <id>/screenshots/<name>; only the second and fourth are files. A prefix may end in "/".
func parts(p string, wantFile bool) ([]string, error) {
	if !wantFile {
		p = strings.TrimSuffix(p, "/")
	}
	segs := strings.Split(p, "/")
	if !claimDir.MatchString(segs[0]) {
		return nil, ErrBadPath
	}
	switch {
	case len(segs) == 1:
		return segs, boolErr(!wantFile)
	case len(segs) == 2 && characterFiles[segs[1]]:
		return segs, nil
	case len(segs) == 2 && segs[1] == shotDir:
		return segs, boolErr(!wantFile)
	case len(segs) == 3 && segs[1] == shotDir && shotFile.MatchString(segs[2]):
		return segs, nil
	}
	return nil, ErrBadPath
}

func boolErr(ok bool) error {
	if ok {
		return nil
	}
	return ErrBadPath
}

func (d *DiskBlobs) resolve(p string, wantFile bool) (string, error) {
	segs, err := parts(p, wantFile)
	if err != nil {
		return "", fmt.Errorf("%w: %q", ErrBadPath, p)
	}
	return filepath.Join(append([]string{d.root}, segs...)...), nil
}

func (d *DiskBlobs) Write(ctx context.Context, p string, r io.Reader) (err error) {
	dst, err := d.resolve(p, true)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(dst), tmpPrefix+"*")
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			tmp.Close()
			os.Remove(tmp.Name())
		}
	}()
	if _, err = io.Copy(tmp, r); err != nil {
		return err
	}
	if err = tmp.Sync(); err != nil {
		return err
	}
	if err = tmp.Close(); err != nil {
		return err
	}
	if err = ctx.Err(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), dst)
}

func (d *DiskBlobs) Open(_ context.Context, p string) (File, error) {
	src, err := d.resolve(p, true)
	if err != nil {
		return nil, err
	}
	return os.Open(src)
}

func (d *DiskBlobs) Remove(_ context.Context, p string) error {
	src, err := d.resolve(p, true)
	if err != nil {
		return err
	}
	if err := os.Remove(src); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

func (d *DiskBlobs) RemoveAll(_ context.Context, prefix string) error {
	dir, err := d.resolve(prefix, false)
	if err != nil {
		return err
	}
	return os.RemoveAll(dir)
}

func (d *DiskBlobs) Size(_ context.Context, prefix string) (int64, error) {
	dir, err := d.resolve(prefix, false)
	if err != nil {
		return 0, err
	}
	var total int64
	err = filepath.WalkDir(dir, func(_ string, e fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if e.Type().IsRegular() && !strings.HasPrefix(e.Name(), tmpPrefix) {
			info, err := e.Info()
			if err != nil {
				return err
			}
			total += info.Size()
		}
		return nil
	})
	if errors.Is(err, fs.ErrNotExist) {
		return 0, nil
	}
	return total, err
}
