package store

import (
	"context"
	"database/sql"
	"errors"
)

// Screenshot approval states of a key.
const (
	ShotsNone     = "none"
	ShotsPending  = "pending"
	ShotsApproved = "approved"
	ShotsDenied   = "denied"
)

// Key is a registered public key.
type Key struct {
	ID          int64
	Public      []byte
	Created     int64
	Screenshots string
	Revoked     bool
	LastSeen    int64
}

// KeyByPublic returns the key with the given 32-byte public key, or ErrNotFound.
func (s *Store) KeyByPublic(ctx context.Context, pub []byte) (Key, error) {
	return scanKey(s.db.QueryRowContext(ctx,
		`SELECT id, public_key, created, screenshots, revoked, COALESCE(last_seen, 0) FROM keys WHERE public_key = ?`, pub))
}

func scanKey(row *sql.Row) (Key, error) {
	var k Key
	var revoked int
	err := row.Scan(&k.ID, &k.Public, &k.Created, &k.Screenshots, &revoked, &k.LastSeen)
	if errors.Is(err, sql.ErrNoRows) {
		return Key{}, ErrNotFound
	}
	k.Revoked = revoked != 0
	return k, err
}

// TouchKey records that the key made a request now.
func (s *Store) TouchKey(ctx context.Context, id int64) error {
	_, err := s.db.ExecContext(ctx, `UPDATE keys SET last_seen = ? WHERE id = ?`, s.now().Unix(), id)
	return err
}

// RegisterInput is the data of one registration request.
type RegisterInput struct {
	Public []byte
	// Nonce of the signed request. A new key has no row to hold it before this call, so Register stores it.
	Nonce  []byte
	Invite string
	// RequireInvite is true in invite mode. In open mode the invite is ignored.
	RequireInvite bool
}

// Register adds the key and, in invite mode, spends the invite in the same transaction, so that a code works once even
// when two registrations race. It returns created false when the key already exists, and ErrKeyRevoked when the admin
// revoked it; a revoked key leaves its invite unused.
func (s *Store) Register(ctx context.Context, in RegisterInput) (created bool, err error) {
	now := s.now().Unix()
	err = s.inTx(ctx, func(tx *sql.Tx) error {
		var id int64
		var revoked int
		switch err := tx.QueryRowContext(ctx, `SELECT id, revoked FROM keys WHERE public_key = ?`, in.Public).Scan(&id, &revoked); {
		case err == nil:
			if revoked != 0 {
				return ErrKeyRevoked
			}
			return nil
		case !errors.Is(err, sql.ErrNoRows):
			return err
		}

		hash := inviteHash(in.Invite)
		if in.RequireInvite && hash == nil {
			return ErrInviteInvalid
		}
		res, err := tx.ExecContext(ctx, `INSERT INTO keys (public_key, created, last_seen) VALUES (?, ?, ?)`, in.Public, now, now)
		if err != nil {
			return err
		}
		if id, err = res.LastInsertId(); err != nil {
			return err
		}
		if in.RequireInvite {
			if err := useInvite(ctx, tx, hash, id, now); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO nonces (key_id, nonce, seen) VALUES (?, ?, ?)`, id, in.Nonce, now); err != nil {
			return err
		}
		created = true
		return nil
	})
	if err != nil {
		return false, err
	}
	return created, nil
}

// RequestScreenshots moves the key from none or denied to pending and returns the state after the call.
// A pending or approved key keeps its state.
func (s *Store) RequestScreenshots(ctx context.Context, id int64) (string, error) {
	var state string
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx,
			`UPDATE keys SET screenshots = 'pending' WHERE id = ? AND screenshots IN ('none', 'denied')`, id); err != nil {
			return err
		}
		err := tx.QueryRowContext(ctx, `SELECT screenshots FROM keys WHERE id = ?`, id).Scan(&state)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return err
	})
	return state, err
}

// RevokeKey blocks the key. It returns ErrNotFound for an id that does not exist.
func (s *Store) RevokeKey(ctx context.Context, id int64) error {
	return s.execOne(ctx, `UPDATE keys SET revoked = 1 WHERE id = ?`, id)
}

// SetScreenshots sets the screenshot state of the key, one of the Shots* constants.
func (s *Store) SetScreenshots(ctx context.Context, id int64, state string) error {
	return s.execOne(ctx, `UPDATE keys SET screenshots = ? WHERE id = ?`, state, id)
}

// execOne runs a statement that targets one row by id, and returns ErrNotFound when it changes no row.
func (s *Store) execOne(ctx context.Context, query string, args ...any) error {
	res, err := s.db.ExecContext(ctx, query, args...)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}
