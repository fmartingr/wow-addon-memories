// Package backup copies the data folder of a running server into a new folder.
package backup

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"

	_ "modernc.org/sqlite"
)

const dbName = "memories.db"

// Result tells what a backup wrote.
type Result struct {
	// Files counts the character files that were copied. The database is not counted.
	Files int
	// Bytes is the size of the copied character files.
	Bytes int64
}

// ErrDestExists means that the destination already exists. A backup never writes into a folder that exists, so an
// old backup is never mixed with a new one.
var ErrDestExists = errors.New("backup: the destination already exists")

// Run writes a copy of dataDir into the new folder dest: memories.db as a consistent snapshot made with
// VACUUM INTO, then the files of characters/ of each claim in that snapshot. It does not stop the server. The
// database is a snapshot of one moment; the character files are copied after it, so they can be newer than the
// database. After a restore, the next upload of each player merges into them. A claim folder is left out when the
// claim is not in the snapshot, or when the live claim with that id is no longer the one of the snapshot after the
// copy: SQLite gives the highest free id to the next claim, so after a restore those files would load into another
// character.
// On an error Run removes the folder that it made.
func Run(ctx context.Context, dataDir, dest string) (res Result, err error) {
	// Without Clean, a trailing "/" makes filepath.Dir return dest itself, and MkdirAll creates it before Mkdir.
	dest = filepath.Clean(dest)
	// A backup below characters/ would be walked into itself, or end up in the folder of a future claim.
	chars := mustAbs(filepath.Join(dataDir, store.CharactersDir))
	if d := mustAbs(dest); d == chars || strings.HasPrefix(d, chars+string(filepath.Separator)) {
		return Result{}, fmt.Errorf("the backup folder %s is inside %s. Choose a folder outside it", dest, chars)
	}
	dbPath := filepath.Join(dataDir, dbName)
	if _, err := os.Stat(dbPath); err != nil {
		return Result{}, fmt.Errorf("there is no database at %s. Check that the data folder is the one of the server: %w", dbPath, err)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o700); err != nil {
		return Result{}, fmt.Errorf("could not create the folder for the backup: %w", err)
	}
	// Mkdir fails when dest exists, so the check and the creation are one step.
	if err := os.Mkdir(dest, 0o700); err != nil {
		if errors.Is(err, fs.ErrExist) {
			return Result{}, fmt.Errorf("%w: %s. Choose a new folder name", ErrDestExists, dest)
		}
		return Result{}, fmt.Errorf("could not create the backup folder %s: %w", dest, err)
	}
	defer func() {
		if err != nil {
			os.RemoveAll(dest)
		}
	}()

	claims, err := snapshot(ctx, dbPath, filepath.Join(dest, dbName))
	if err != nil {
		return Result{}, err
	}
	res, err = copyClaims(ctx, dbPath, filepath.Join(dataDir, store.CharactersDir), filepath.Join(dest, store.CharactersDir), claims)
	return res, err
}

// snapshot writes the database to dst and returns the identity of each claim that the copy holds, by claim id. The
// connection is separate from the one of the server; in WAL mode a reader does not block the writer of the server,
// and the busy timeout covers the short moments that it has to wait.
func snapshot(ctx context.Context, src, dst string) (map[string]string, error) {
	db, err := openLive(src)
	if err != nil {
		return nil, err
	}
	defer db.Close()
	if _, err := db.ExecContext(ctx, "VACUUM INTO ?", mustAbs(dst)); err != nil {
		return nil, fmt.Errorf("could not copy the database: %w", err)
	}
	if err := os.Chmod(dst, 0o600); err != nil {
		return nil, err
	}
	copied, err := sql.Open("sqlite", fileDSN(dst, "mode=ro"))
	if err != nil {
		return nil, err
	}
	defer copied.Close()
	claims, err := identities(ctx, copied)
	if err != nil {
		return nil, fmt.Errorf("could not read the claims of the copied database: %w", err)
	}
	return claims, nil
}

// openLive opens the database of the server. mode=rw: never create an empty database when the file is gone.
func openLive(path string) (*sql.DB, error) {
	return sql.Open("sqlite", fileDSN(path, "mode=rw&_pragma=busy_timeout(5000)"))
}

// identities returns the identity of each claim by id.
func identities(ctx context.Context, db *sql.DB) (map[string]string, error) {
	rows, err := db.QueryContext(ctx, `SELECT id, flavor, region, realm, name, guid, created FROM claims`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := map[string]string{}
	for rows.Next() {
		var id, created int64
		var flavor, region, realm, name, guid string
		if err := rows.Scan(&id, &flavor, &region, &realm, &name, &guid, &created); err != nil {
			return nil, err
		}
		ids[strconv.FormatInt(id, 10)] = strings.Join([]string{flavor, region, realm, name, guid, strconv.FormatInt(created, 10)}, "\x00")
	}
	return ids, rows.Err()
}

func fileDSN(path, query string) string {
	return (&url.URL{Scheme: "file", Path: filepath.ToSlash(mustAbs(path)), RawQuery: query}).String()
}

func mustAbs(p string) string {
	abs, err := filepath.Abs(p)
	if err != nil {
		return p
	}
	return abs
}

// copyClaims copies the folder of each claim in claims from src into dst. After all the copies it reads the live
// claims once; when a claim was deleted or its id was given to another claim while the copy ran, its copied folder is
// removed. An identity never comes back once it changed, so one read after the copies catches every change that a
// read after each copy would. A missing src is an empty tree.
func copyClaims(ctx context.Context, dbPath, src, dst string, claims map[string]string) (Result, error) {
	if info, err := os.Lstat(src); err == nil && !info.IsDir() {
		return Result{}, fmt.Errorf("could not copy the character files: %s is not a folder", src)
	}
	if err := os.MkdirAll(dst, 0o700); err != nil {
		return Result{}, fmt.Errorf("could not create the folder %s: %w", dst, err)
	}
	parts := make(map[string]Result, len(claims))
	for id := range claims {
		var part Result
		if err := copyTree(ctx, filepath.Join(src, id), filepath.Join(dst, id), &part); err != nil {
			return Result{}, fmt.Errorf("could not copy the character files: %w", err)
		}
		parts[id] = part
	}
	live, err := openLive(dbPath)
	if err != nil {
		return Result{}, err
	}
	defer live.Close()
	now, err := identities(ctx, live)
	if err != nil {
		return Result{}, fmt.Errorf("could not read the claims of the database: %w", err)
	}
	var res Result
	for id, identity := range claims {
		if now[id] != identity {
			if err := os.RemoveAll(filepath.Join(dst, id)); err != nil {
				return Result{}, err
			}
			continue
		}
		res.Files += parts[id].Files
		res.Bytes += parts[id].Bytes
	}
	return res, nil
}

// copyTree copies the regular files below src into dst, each through a temporary file and a rename. A missing src is
// an empty tree. A file that the server deletes while the copy runs is skipped.
func copyTree(ctx context.Context, src, dst string, res *Result) error {
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		switch {
		case d.IsDir():
			return os.MkdirAll(target, 0o700)
		case !d.Type().IsRegular() || strings.HasPrefix(d.Name(), store.TmpPrefix):
			return nil
		}
		n, err := copyFile(path, target)
		if errors.Is(err, fs.ErrNotExist) {
			return nil
		}
		if err != nil {
			return err
		}
		res.Files++
		res.Bytes += n
		return nil
	})
}

func copyFile(src, dst string) (n int64, err error) {
	in, err := os.Open(src)
	if err != nil {
		return 0, err
	}
	defer in.Close()
	tmp, err := os.CreateTemp(filepath.Dir(dst), store.TmpPrefix+"*")
	if err != nil {
		return 0, err
	}
	defer func() {
		if err != nil {
			tmp.Close()
			os.Remove(tmp.Name())
		}
	}()
	if n, err = io.Copy(tmp, in); err != nil {
		return 0, err
	}
	if err = tmp.Sync(); err != nil {
		return 0, err
	}
	// CreateTemp makes the file 0600, so the copy needs no chmod.
	if err = tmp.Close(); err != nil {
		return 0, err
	}
	return n, os.Rename(tmp.Name(), dst)
}
