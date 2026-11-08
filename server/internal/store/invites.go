package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"errors"
	"strings"
	"time"
)

const (
	// crockford is the Crockford base32 alphabet: no I, L, O or U, so a code read aloud or typed from a screen stays unambiguous.
	crockford  = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
	codeLength = 16
)

// newInviteCode returns 16 Crockford base32 characters (80 bits) from crypto/rand.
func newInviteCode() (string, error) {
	raw := make([]byte, codeLength)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	for i, b := range raw {
		raw[i] = crockford[b&31]
	}
	return string(raw), nil
}

// inviteHash returns the SHA-256 of the normalized code, or nil when the text cannot be a code. The server never
// stores a code, only this hash. Normalizing follows Crockford: case does not matter, I and L read as 1, O reads as 0,
// and spaces and dashes are dropped.
func inviteHash(code string) []byte {
	var b strings.Builder
	for _, c := range strings.ToUpper(code) {
		switch c {
		case ' ', '-':
			continue
		case 'I', 'L':
			c = '1'
		case 'O':
			c = '0'
		}
		b.WriteRune(c)
	}
	norm := b.String()
	if len(norm) != codeLength || strings.Trim(norm, crockford) != "" {
		return nil
	}
	sum := sha256.Sum256([]byte(norm))
	return sum[:]
}

// CreateInvite makes a single-use code that is valid for ttl and returns it. This is the only time the code is visible.
func (s *Store) CreateInvite(ctx context.Context, note string, ttl time.Duration) (id int64, code string, err error) {
	code, err = newInviteCode()
	if err != nil {
		return 0, "", err
	}
	now := s.now()
	res, err := s.db.ExecContext(ctx, `INSERT INTO invites (code_hash, note, created, expires) VALUES (?, ?, ?, ?)`,
		inviteHash(code), note, now.Unix(), now.Add(ttl).Unix())
	if err != nil {
		return 0, "", err
	}
	id, err = res.LastInsertId()
	return id, code, err
}

// RevokeInvite makes the invite unusable. It returns ErrNotFound for an id that does not exist.
func (s *Store) RevokeInvite(ctx context.Context, id int64) error {
	return s.execOne(ctx, `UPDATE invites SET revoked = 1 WHERE id = ?`, id)
}

// useInvite spends the invite for the key. A single UPDATE with the whole validity test makes the use atomic: of two
// registrations with one code, only one changes a row.
func useInvite(ctx context.Context, tx *sql.Tx, hash []byte, keyID, now int64) error {
	var inviteID int64
	err := tx.QueryRowContext(ctx,
		`UPDATE invites SET used_by = ?, used_at = ? WHERE code_hash = ? AND used_by IS NULL AND revoked = 0 AND expires > ?
		 RETURNING id`,
		keyID, now, hash, now).Scan(&inviteID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInviteInvalid
	}
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE keys SET invite_id = ? WHERE id = ?`, inviteID, keyID)
	return err
}
