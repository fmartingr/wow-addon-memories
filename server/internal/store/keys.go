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
	// Open is true for a key that registered without an invite. An open key can never upload screenshots.
	Open bool
	// MaxDataBytes and MaxShotBytes are the storage limits that the admin set for this key. 0 means the default limit.
	MaxDataBytes int64
	MaxShotBytes int64
}

// DataLimit is the most journey data that the key may hold: its own limit, else openLimit for an open key, else
// defaultLimit.
func (k Key) DataLimit(openLimit, defaultLimit int64) int64 {
	switch {
	case k.MaxDataBytes > 0:
		return k.MaxDataBytes
	case k.Open:
		return openLimit
	}
	return defaultLimit
}

// ShotLimit is the most screenshot data that the key may hold: its own limit, else defaultLimit.
func (k Key) ShotLimit(defaultLimit int64) int64 {
	if k.MaxShotBytes > 0 {
		return k.MaxShotBytes
	}
	return defaultLimit
}

const keyColumns = `id, public_key, created, screenshots, revoked, COALESCE(last_seen, 0), open, max_data_bytes, max_shot_bytes`

// KeyByPublic returns the key with the given 32-byte public key, or ErrNotFound.
func (s *Store) KeyByPublic(ctx context.Context, pub []byte) (Key, error) {
	return scanKey(s.db.QueryRowContext(ctx,
		`SELECT `+keyColumns+` FROM keys WHERE public_key = ?`, pub))
}

func scanKey(row *sql.Row) (Key, error) {
	var k Key
	var revoked, open int
	err := row.Scan(&k.ID, &k.Public, &k.Created, &k.Screenshots, &revoked, &k.LastSeen, &open, &k.MaxDataBytes, &k.MaxShotBytes)
	if errors.Is(err, sql.ErrNoRows) {
		return Key{}, ErrNotFound
	}
	k.Revoked, k.Open = revoked != 0, open != 0
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
	// AllowOpen lets a new key with no invite register as an open key.
	AllowOpen bool
}

// Register adds the key. With an invite, it spends the invite in the same transaction, so that a code works once even
// when two registrations race. With AllowOpen, a key with no invite, or with a code that does not work, is an open key. It returns created false when the
// key already exists, and ErrKeyRevoked when the admin revoked it; a revoked key leaves its invite unused. An existing
// key needs neither an invite nor AllowOpen, so a key keeps working after open registration closes.
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
		open := hash == nil
		if open && !in.AllowOpen {
			return ErrInviteInvalid
		}
		res, err := tx.ExecContext(ctx, `INSERT INTO keys (public_key, created, last_seen, open) VALUES (?, ?, ?, ?)`,
			in.Public, now, now, open)
		if err != nil {
			return err
		}
		if id, err = res.LastInsertId(); err != nil {
			return err
		}
		if !open {
			err := useInvite(ctx, tx, hash, id, now)
			switch {
			case errors.Is(err, ErrInviteInvalid) && in.AllowOpen:
				if _, err := tx.ExecContext(ctx, `UPDATE keys SET open = 1 WHERE id = ?`, id); err != nil {
					return err
				}
			case err != nil:
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
// A pending or approved key keeps its state, and so does an open key.
func (s *Store) RequestScreenshots(ctx context.Context, id int64) (string, error) {
	var state string
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx,
			`UPDATE keys SET screenshots = 'pending' WHERE id = ? AND screenshots IN ('none', 'denied') AND open = 0`, id); err != nil {
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

// SetKeyLimits sets the storage limits of the key. 0 means the default limit. It returns ErrNotFound for an id that
// does not exist.
func (s *Store) SetKeyLimits(ctx context.Context, id, maxDataBytes, maxShotBytes int64) error {
	return s.execOne(ctx, `UPDATE keys SET max_data_bytes = ?, max_shot_bytes = ? WHERE id = ?`, maxDataBytes, maxShotBytes, id)
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
