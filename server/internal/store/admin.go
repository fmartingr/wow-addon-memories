package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"database/sql/driver"
	"encoding/hex"
	"errors"
	"strings"

	"modernc.org/sqlite"
)

func init() {
	// SQLite has no SHA-256, so the admin search reaches the fingerprint of a key through this function.
	sqlite.MustRegisterDeterministicScalarFunction("fingerprint", 1, func(_ *sqlite.FunctionContext, args []driver.Value) (driver.Value, error) {
		pub, ok := args[0].([]byte)
		if !ok {
			return nil, nil
		}
		return Fingerprint(pub), nil
	})
}

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

// Listing is one page of a list, with the figures for the pager.
type Listing[T any] struct {
	Rows []T
	// Total is the number of rows that match, on every page.
	Total int
	// Page is the page that Rows holds, 1-based. It is the requested page clamped to 1..Pages.
	Page  int
	Pages int
}

// likePattern turns a search text into a LIKE pattern that matches rows containing the text. The wildcards of LIKE
// in the text are literal; use it with ESCAPE '\'.
func likePattern(q string, prefix bool) string {
	p := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(strings.TrimSpace(q))
	if prefix {
		return p + "%"
	}
	return "%" + p + "%"
}

// paged counts the rows of "FROM ... WHERE ..." and clamps the page, so a page past the end shows the last page.
// It returns the listing without rows and the offset of the page.
func paged[T any](ctx context.Context, s *Store, from string, args []any, page, size int) (l Listing[T], offset int, err error) {
	if err = s.db.QueryRowContext(ctx, `SELECT COUNT(*) `+from, args...).Scan(&l.Total); err != nil {
		return l, 0, err
	}
	l.Pages = max(1, (l.Total+size-1)/size)
	l.Page = min(max(page, 1), l.Pages)
	return l, (l.Page - 1) * size, nil
}

const keyFrom = `FROM keys k LEFT JOIN invites i ON i.id = k.invite_id`

// ListKeys returns one page of the keys, newest first. A q other than "" keeps the keys whose fingerprint, invite note
// or screenshot state contains it, ignoring case; "open" also finds the open keys.
func (s *Store) ListKeys(ctx context.Context, q string, page, size int) (Listing[KeyRow], error) {
	where, args := ``, []any(nil)
	if strings.TrimSpace(q) != "" {
		like := likePattern(q, false)
		where = ` WHERE (fingerprint(k.public_key) LIKE ? ESCAPE '\' OR COALESCE(i.note, '') LIKE ? ESCAPE '\' OR k.screenshots LIKE ? ESCAPE '\' OR (k.open = 1 AND 'open' LIKE ? ESCAPE '\'))`
		args = []any{like, like, like, like}
	}
	return s.listKeys(ctx, where, args, `k.id DESC`, page, size)
}

// ListRequests returns one page of the keys that wait for a screenshot decision, oldest first, without revoked keys.
// A q other than "" keeps the keys whose fingerprint or invite note contains it, ignoring case.
func (s *Store) ListRequests(ctx context.Context, q string, page, size int) (Listing[KeyRow], error) {
	where, args := ` WHERE k.screenshots = 'pending' AND k.revoked = 0`, []any(nil)
	if strings.TrimSpace(q) != "" {
		like := likePattern(q, false)
		where += ` AND (fingerprint(k.public_key) LIKE ? ESCAPE '\' OR COALESCE(i.note, '') LIKE ? ESCAPE '\')`
		args = []any{like, like}
	}
	return s.listKeys(ctx, where, args, `k.id`, page, size)
}

func (s *Store) listKeys(ctx context.Context, where string, args []any, order string, page, size int) (Listing[KeyRow], error) {
	l, offset, err := paged[KeyRow](ctx, s, keyFrom+where, args, page, size)
	if err != nil {
		return l, err
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT k.id, k.public_key, k.created, k.screenshots, k.revoked, COALESCE(k.last_seen, 0), k.open, k.max_data_bytes, k.max_shot_bytes, COALESCE(i.note, ''),
		        COALESCE(c.n, 0), COALESCE(c.data, 0), COALESCE(c.shots, 0)
		 `+keyFrom+`
		 LEFT JOIN (SELECT key_id, COUNT(*) AS n, SUM(data_bytes) AS data, SUM(shot_bytes) AS shots
		            FROM claims GROUP BY key_id) c ON c.key_id = k.id`+where+` ORDER BY `+order+` LIMIT ? OFFSET ?`,
		append(args, size, offset)...)
	if err != nil {
		return l, err
	}
	defer rows.Close()
	for rows.Next() {
		var r KeyRow
		var revoked, open int
		if err := rows.Scan(&r.ID, &r.Public, &r.Created, &r.Screenshots, &revoked, &r.LastSeen, &open, &r.MaxDataBytes, &r.MaxShotBytes, &r.InviteNote,
			&r.Characters, &r.DataBytes, &r.ShotBytes); err != nil {
			return l, err
		}
		r.Revoked, r.Open = revoked != 0, open != 0
		l.Rows = append(l.Rows, r)
	}
	return l, rows.Err()
}

// KeyByID returns the key, or ErrNotFound.
func (s *Store) KeyByID(ctx context.Context, id int64) (Key, error) {
	return scanKey(s.db.QueryRowContext(ctx,
		`SELECT `+keyColumns+` FROM keys WHERE id = ?`, id))
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
		`UPDATE keys SET screenshots = ? WHERE id = ? AND screenshots = 'pending' AND revoked = 0 AND open = 0`, state, id)
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

// inviteState is the state of an invite as the search sees it. A use comes first, so a revoke does not hide who used
// the invite. It takes the current time as its only parameter.
const inviteState = `CASE WHEN i.used_by IS NOT NULL THEN 'used' WHEN i.revoked != 0 THEN 'revoked'
	WHEN i.expires <= ? THEN 'expired' ELSE 'unused' END`

// ListInvites returns one page of the invites, newest first. A q other than "" keeps the invites whose note contains
// it, or whose state (unused, used, expired or revoked) starts with it, ignoring case. A state matches from its
// start, so "used" finds the used invites and not the unused ones.
func (s *Store) ListInvites(ctx context.Context, q string, page, size int) (Listing[InviteRow], error) {
	now := s.now().Unix()
	where, args := ``, []any(nil)
	if strings.TrimSpace(q) != "" {
		where = ` WHERE (i.note LIKE ? ESCAPE '\' OR ` + inviteState + ` LIKE ? ESCAPE '\')`
		args = []any{likePattern(q, false), now, likePattern(q, true)}
	}
	const from = `FROM invites i LEFT JOIN keys k ON k.id = i.used_by`
	l, offset, err := paged[InviteRow](ctx, s, from+where, args, page, size)
	if err != nil {
		return l, err
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT i.id, i.note, i.created, i.expires, i.revoked, COALESCE(i.used_at, 0), k.public_key `+from+where+
			` ORDER BY i.id DESC LIMIT ? OFFSET ?`, append(args, size, offset)...)
	if err != nil {
		return l, err
	}
	defer rows.Close()
	for rows.Next() {
		var r InviteRow
		var revoked int
		var pub []byte
		if err := rows.Scan(&r.ID, &r.Note, &r.Created, &r.Expires, &revoked, &r.UsedAt, &pub); err != nil {
			return l, err
		}
		r.Revoked = revoked != 0
		if pub != nil {
			r.UsedBy = Fingerprint(pub)
		}
		l.Rows = append(l.Rows, r)
	}
	return l, rows.Err()
}

// ClaimRow is a claim with its owner, for the admin page.
type ClaimRow struct {
	Claim
	OwnerKey     []byte
	OwnerRevoked bool
}

// SearchClaims returns one page of the claims ordered by path. A q other than "" keeps the claims whose path, GUID or
// owner fingerprint contains it, ignoring case.
func (s *Store) SearchClaims(ctx context.Context, q string, page, size int) (Listing[ClaimRow], error) {
	where, args := ``, []any(nil)
	if strings.TrimSpace(q) != "" {
		like := likePattern(q, false)
		where = ` WHERE (c.flavor || '/' || c.region || '/' || c.realm || '/' || c.name LIKE ? ESCAPE '\' OR c.guid LIKE ? ESCAPE '\'
		              OR fingerprint(k.public_key) LIKE ? ESCAPE '\')`
		args = []any{like, like, like}
	}
	const from = `FROM claims c JOIN keys k ON k.id = c.key_id`
	l, offset, err := paged[ClaimRow](ctx, s, from+where, args, page, size)
	if err != nil {
		return l, err
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT c.id, c.flavor, c.region, c.realm, c.name, c.guid, c.key_id, c.created, c.updated, c.steps, c.data_bytes,
		        c.shot_bytes, k.public_key, k.revoked `+from+where+
			` ORDER BY c.flavor, c.region, c.realm, c.name LIMIT ? OFFSET ?`, append(args, size, offset)...)
	if err != nil {
		return l, err
	}
	defer rows.Close()
	for rows.Next() {
		var r ClaimRow
		var revoked int
		if err := rows.Scan(&r.ID, &r.Flavor, &r.Region, &r.Realm, &r.Name, &r.GUID, &r.KeyID, &r.Created, &r.Updated,
			&r.Steps, &r.DataBytes, &r.ShotBytes, &r.OwnerKey, &revoked); err != nil {
			return l, err
		}
		r.OwnerRevoked = revoked != 0
		l.Rows = append(l.Rows, r)
	}
	return l, rows.Err()
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
