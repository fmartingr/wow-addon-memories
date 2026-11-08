package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"strings"
)

// Fingerprint is the first 16 hex characters of the SHA-256 of a public key. The admin page and the upload client show
// it, so a person can tell keys apart without reading a 43-character key.
func Fingerprint(pub []byte) string {
	sum := sha256.Sum256(pub)
	return hex.EncodeToString(sum[:8])
}

// KeyRow is a key with the figures that the admin page shows.
type KeyRow struct {
	Key
	InviteNote string
	Characters int64
	DataBytes  int64
	ShotBytes  int64
}

// Fingerprint returns the fingerprint of the key.
func (k Key) Fingerprint() string { return Fingerprint(k.Public) }

// ListKeys returns the newest keys first, at most limit. With pendingOnly it returns the keys that wait for a
// screenshot decision, oldest request first by key id, and skips revoked keys.
func (s *Store) ListKeys(ctx context.Context, pendingOnly bool, limit int) ([]KeyRow, error) {
	where, order := ``, `k.id DESC`
	if pendingOnly {
		where, order = `WHERE k.screenshots = 'pending' AND k.revoked = 0`, `k.id`
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT k.id, k.public_key, k.created, k.screenshots, k.revoked, COALESCE(k.last_seen, 0), COALESCE(i.note, ''),
		        COALESCE(c.n, 0), COALESCE(c.data, 0), COALESCE(c.shots, 0)
		 FROM keys k LEFT JOIN invites i ON i.id = k.invite_id
		 LEFT JOIN (SELECT key_id, COUNT(*) AS n, SUM(data_bytes) AS data, SUM(shot_bytes) AS shots
		            FROM claims GROUP BY key_id) c ON c.key_id = k.id `+where+` ORDER BY `+order+` LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []KeyRow
	for rows.Next() {
		var r KeyRow
		var revoked int
		if err := rows.Scan(&r.ID, &r.Public, &r.Created, &r.Screenshots, &revoked, &r.LastSeen, &r.InviteNote,
			&r.Characters, &r.DataBytes, &r.ShotBytes); err != nil {
			return nil, err
		}
		r.Revoked = revoked != 0
		out = append(out, r)
	}
	return out, rows.Err()
}

// KeyByID returns the key, or ErrNotFound.
func (s *Store) KeyByID(ctx context.Context, id int64) (Key, error) {
	return scanKey(s.db.QueryRowContext(ctx,
		`SELECT id, public_key, created, screenshots, revoked, COALESCE(last_seen, 0) FROM keys WHERE id = ?`, id))
}

// KeyByFingerprint returns the key with this fingerprint, or ErrNotFound. SQLite has no SHA-256, so it compares in Go.
func (s *Store) KeyByFingerprint(ctx context.Context, fingerprint string) (Key, error) {
	fingerprint = strings.ToLower(strings.TrimSpace(fingerprint))
	rows, err := s.db.QueryContext(ctx, `SELECT id, public_key FROM keys`)
	if err != nil {
		return Key{}, err
	}
	var id int64 = -1
	for rows.Next() {
		var rowID int64
		var pub []byte
		if err := rows.Scan(&rowID, &pub); err != nil {
			rows.Close()
			return Key{}, err
		}
		if Fingerprint(pub) == fingerprint {
			id = rowID
			break
		}
	}
	// Close before the next query: the store has one connection.
	rows.Close()
	if err := rows.Err(); err != nil {
		return Key{}, err
	}
	if id < 0 {
		return Key{}, ErrNotFound
	}
	return s.KeyByID(ctx, id)
}

// DecideScreenshots moves a key from pending to state (approved or denied). It changes nothing, and returns false,
// when the key is not pending or is revoked, so a stale form cannot undo a later decision.
func (s *Store) DecideScreenshots(ctx context.Context, id int64, state string) (bool, error) {
	res, err := s.db.ExecContext(ctx,
		`UPDATE keys SET screenshots = ? WHERE id = ? AND screenshots = 'pending' AND revoked = 0`, state, id)
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	return n > 0, err
}

// InviteRow is an invite as the admin page lists it.
type InviteRow struct {
	ID      int64
	Note    string
	Created int64
	Expires int64
	Revoked bool
	UsedAt  int64
	// UsedBy is the fingerprint of the key that spent the invite, or empty.
	UsedBy string
}

// ListInvites returns the newest invites first, at most limit.
func (s *Store) ListInvites(ctx context.Context, limit int) ([]InviteRow, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT i.id, i.note, i.created, i.expires, i.revoked, COALESCE(i.used_at, 0), k.public_key
		 FROM invites i LEFT JOIN keys k ON k.id = i.used_by ORDER BY i.id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []InviteRow
	for rows.Next() {
		var r InviteRow
		var revoked int
		var pub []byte
		if err := rows.Scan(&r.ID, &r.Note, &r.Created, &r.Expires, &revoked, &r.UsedAt, &pub); err != nil {
			return nil, err
		}
		r.Revoked = revoked != 0
		if pub != nil {
			r.UsedBy = Fingerprint(pub)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// ClaimRow is a claim with its owner, for the admin page.
type ClaimRow struct {
	Claim
	OwnerKey     []byte
	OwnerRevoked bool
}

// SearchClaims returns the claims whose path or GUID contains q, ignoring case, ordered by path, at most limit.
// An empty q matches every claim. A keyID other than 0 keeps the claims of that key only.
func (s *Store) SearchClaims(ctx context.Context, q string, keyID int64, limit int) ([]ClaimRow, error) {
	like := "%" + strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(strings.ToLower(strings.TrimSpace(q))) + "%"
	rows, err := s.db.QueryContext(ctx,
		`SELECT c.id, c.flavor, c.region, c.realm, c.name, c.guid, c.key_id, c.created, c.updated, c.steps, c.data_bytes,
		        c.shot_bytes, k.public_key, k.revoked
		 FROM claims c JOIN keys k ON k.id = c.key_id
		 WHERE (? = 0 OR c.key_id = ?)
		   AND (c.flavor || '/' || c.region || '/' || c.realm || '/' || c.name LIKE ? ESCAPE '\' OR lower(c.guid) LIKE ? ESCAPE '\')
		 ORDER BY c.flavor, c.region, c.realm, c.name LIMIT ?`, keyID, keyID, like, like, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ClaimRow
	for rows.Next() {
		var r ClaimRow
		var revoked int
		if err := rows.Scan(&r.ID, &r.Flavor, &r.Region, &r.Realm, &r.Name, &r.GUID, &r.KeyID, &r.Created, &r.Updated,
			&r.Steps, &r.DataBytes, &r.ShotBytes, &r.OwnerKey, &revoked); err != nil {
			return nil, err
		}
		r.OwnerRevoked = revoked != 0
		out = append(out, r)
	}
	return out, rows.Err()
}

// MoveClaim gives the claim to another key. The target must exist (else ErrNotFound) and not be revoked (else
// ErrKeyRevoked); both are checked in the same transaction as the change. A claim id that does not exist gives ErrNotFound.
func (s *Store) MoveClaim(ctx context.Context, claimID, toKey int64) error {
	return s.inTx(ctx, func(tx *sql.Tx) error {
		var revoked int
		err := tx.QueryRowContext(ctx, `SELECT revoked FROM keys WHERE id = ?`, toKey).Scan(&revoked)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if revoked != 0 {
			return ErrKeyRevoked
		}
		res, err := tx.ExecContext(ctx, `UPDATE claims SET key_id = ? WHERE id = ?`, toKey, claimID)
		if err != nil {
			return err
		}
		if n, err := res.RowsAffected(); err != nil {
			return err
		} else if n == 0 {
			return ErrNotFound
		}
		return nil
	})
}

// ClearShots forgets every stored screenshot of the claim and sets its shot_bytes to 0. The files belong to the caller.
func (s *Store) ClearShots(ctx context.Context, claimID int64) error {
	return s.inTx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM shots WHERE claim_id = ?`, claimID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `UPDATE claims SET shot_bytes = 0 WHERE id = ?`, claimID)
		return err
	})
}
