package store

import (
	"context"
	"database/sql"
	"errors"
)

// ErrClaimQuota means that the key already owns the most characters that it may.
var ErrClaimQuota = errors.New("store: the key owns too many characters")

// Claim is the ownership of one character path.
type Claim struct {
	ID        int64
	Flavor    string
	Region    string
	Realm     string
	Name      string
	GUID      string
	KeyID     int64
	Created   int64
	Updated   int64
	Steps     int64
	DataBytes int64
	ShotBytes int64
}

// Path returns <flavor>/<region>/<realm>/<name>.
func (c Claim) Path() string { return c.Flavor + "/" + c.Region + "/" + c.Realm + "/" + c.Name }

// execer is what insertClaim needs of a *sql.DB or a *sql.Tx.
type execer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// insertClaim inserts the claim, sets its Created and Updated to now when they are 0, and returns its id.
func (s *Store) insertClaim(ctx context.Context, db execer, c Claim) (int64, error) {
	now := s.now().Unix()
	if c.Created == 0 {
		c.Created = now
	}
	if c.Updated == 0 {
		c.Updated = now
	}
	res, err := db.ExecContext(ctx,
		`INSERT INTO claims (flavor, region, realm, name, guid, key_id, created, updated, steps, data_bytes, shot_bytes)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		c.Flavor, c.Region, c.Realm, c.Name, c.GUID, c.KeyID, c.Created, c.Updated, c.Steps, c.DataBytes, c.ShotBytes)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// CreateClaim inserts the claim, sets its Created and Updated to now when they are 0, and returns its id.
func (s *Store) CreateClaim(ctx context.Context, c Claim) (int64, error) {
	return s.insertClaim(ctx, s.db, c)
}

const claimColumns = `id, flavor, region, realm, name, guid, key_id, created, updated, steps, data_bytes, shot_bytes`

// scanClaim reads one row of claimColumns.
func scanClaim(row interface{ Scan(...any) error }) (Claim, error) {
	var c Claim
	err := row.Scan(&c.ID, &c.Flavor, &c.Region, &c.Realm, &c.Name, &c.GUID, &c.KeyID, &c.Created, &c.Updated,
		&c.Steps, &c.DataBytes, &c.ShotBytes)
	return c, err
}

// ClaimsOfKey returns the claims of the key, ordered by path.
func (s *Store) ClaimsOfKey(ctx context.Context, keyID int64) ([]Claim, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT `+claimColumns+` FROM claims WHERE key_id = ? ORDER BY flavor, region, realm, name`, keyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Claim
	for rows.Next() {
		c, err := scanClaim(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ClaimByPath returns the claim of a character path, or ErrNotFound.
func (s *Store) ClaimByPath(ctx context.Context, flavor, region, realm, name string) (Claim, error) {
	c, err := scanClaim(s.db.QueryRowContext(ctx,
		`SELECT `+claimColumns+` FROM claims WHERE flavor = ? AND region = ? AND realm = ? AND name = ?`,
		flavor, region, realm, name))
	if errors.Is(err, sql.ErrNoRows) {
		return Claim{}, ErrNotFound
	}
	return c, err
}

// CreateClaimWithin inserts the claim like CreateClaim, unless the key owns maxClaims characters already, which
// gives ErrClaimQuota. The count and the insert share one transaction, so two new paths of one key at the same
// time cannot both pass the check.
func (s *Store) CreateClaimWithin(ctx context.Context, c Claim, maxClaims int64) (int64, error) {
	var id int64
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		var n int64
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM claims WHERE key_id = ?`, c.KeyID).Scan(&n); err != nil {
			return err
		}
		if n >= maxClaims {
			return ErrClaimQuota
		}
		var err error
		id, err = s.insertClaim(ctx, tx, c)
		return err
	})
	return id, err
}

// DataBytesOfKey returns the sum of data_bytes over the claims of the key, leaving out the claim with id except.
func (s *Store) DataBytesOfKey(ctx context.Context, keyID, except int64) (int64, error) {
	var n int64
	err := s.db.QueryRowContext(ctx,
		`SELECT COALESCE(SUM(data_bytes), 0) FROM claims WHERE key_id = ? AND id <> ?`, keyID, except).Scan(&n)
	return n, err
}

// SetClaimData records the steps and the data bytes of the claim after a write, and sets updated to now.
func (s *Store) SetClaimData(ctx context.Context, id, steps, dataBytes int64) error {
	return s.execOne(ctx, `UPDATE claims SET steps = ?, data_bytes = ?, updated = ? WHERE id = ?`,
		steps, dataBytes, s.now().Unix(), id)
}

// DeleteClaim removes the claim row. The files of the claim belong to the caller, who removes them first.
func (s *Store) DeleteClaim(ctx context.Context, id int64) error {
	return s.execOne(ctx, `DELETE FROM claims WHERE id = ?`, id)
}
