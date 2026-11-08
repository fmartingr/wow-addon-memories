package store

import (
	"context"
)

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

// CreateClaim inserts the claim, sets its Created and Updated to now when they are 0, and returns its id.
func (s *Store) CreateClaim(ctx context.Context, c Claim) (int64, error) {
	now := s.now().Unix()
	if c.Created == 0 {
		c.Created = now
	}
	if c.Updated == 0 {
		c.Updated = now
	}
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO claims (flavor, region, realm, name, guid, key_id, created, updated, steps, data_bytes, shot_bytes)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		c.Flavor, c.Region, c.Realm, c.Name, c.GUID, c.KeyID, c.Created, c.Updated, c.Steps, c.DataBytes, c.ShotBytes)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// ClaimsOfKey returns the claims of the key, ordered by path.
func (s *Store) ClaimsOfKey(ctx context.Context, keyID int64) ([]Claim, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, flavor, region, realm, name, guid, key_id, created, updated, steps, data_bytes, shot_bytes
		 FROM claims WHERE key_id = ? ORDER BY flavor, region, realm, name`, keyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Claim
	for rows.Next() {
		var c Claim
		if err := rows.Scan(&c.ID, &c.Flavor, &c.Region, &c.Realm, &c.Name, &c.GUID, &c.KeyID, &c.Created, &c.Updated,
			&c.Steps, &c.DataBytes, &c.ShotBytes); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}
