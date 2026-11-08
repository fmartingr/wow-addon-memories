// Package store keeps keys, invites, claims and nonces in SQLite, and the character files on disk behind Blobs.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

var (
	// ErrNotFound means that no row matches.
	ErrNotFound = errors.New("store: not found")
	// ErrKeyRevoked means that the key exists and the admin revoked it.
	ErrKeyRevoked = errors.New("store: key revoked")
	// ErrInviteInvalid means that the invite code is missing, unknown, used, expired or revoked.
	ErrInviteInvalid = errors.New("store: invite code is not valid")
)

// Store is the SQLite database. It has one connection, so every write is serialized and a transaction never meets
// SQLITE_BUSY from this process.
type Store struct {
	db  *sql.DB
	now func() time.Time
}

// Open opens the database file, creating it when it does not exist, and migrates it to the current schema.
func Open(path string) (*Store, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	// SQLite creates the file with the umask and gives the -wal and -shm files the same mode, so the file is created
	// first, readable by the server user only.
	f, err := os.OpenFile(abs, os.O_RDONLY|os.O_CREATE, 0o600)
	if err != nil {
		return nil, fmt.Errorf("could not open the database %s: %w", path, err)
	}
	f.Close()
	// The path goes through url.URL so that a "?" or "#" in a folder name stays part of the file name.
	dsn := (&url.URL{
		Scheme:   "file",
		Path:     filepath.ToSlash(abs),
		RawQuery: "_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)",
	}).String()
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	s := &Store{db: db, now: time.Now}
	if err := s.migrate(context.Background()); err != nil {
		db.Close()
		return nil, fmt.Errorf("could not open the database %s: %w", path, err)
	}
	return s, nil
}

// Close closes the database.
func (s *Store) Close() error { return s.db.Close() }

// SetClock replaces the clock. Call it before the first use; tests use it to move time.
func (s *Store) SetClock(now func() time.Time) { s.now = now }

// Now returns the time of the store clock.
func (s *Store) Now() time.Time { return s.now() }

// inTx runs fn in a transaction: it commits when fn returns nil and rolls back otherwise.
func (s *Store) inTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}
