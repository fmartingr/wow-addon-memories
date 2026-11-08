package store

import (
	"context"
	"database/sql"
	"fmt"
)

// migrations[i] moves the schema from version i to i+1. Each one runs in its own transaction together with the
// update of PRAGMA user_version, so a failed step leaves the file at the last good version.
var migrations = []string{
	`CREATE TABLE invites (
		id INTEGER PRIMARY KEY,
		code_hash BLOB NOT NULL UNIQUE,
		note TEXT NOT NULL DEFAULT '',
		created INTEGER NOT NULL,
		expires INTEGER NOT NULL,
		used_by INTEGER REFERENCES keys(id),
		used_at INTEGER,
		revoked INTEGER NOT NULL DEFAULT 0
	);
	CREATE TABLE keys (
		id INTEGER PRIMARY KEY,
		public_key BLOB NOT NULL UNIQUE,
		created INTEGER NOT NULL,
		invite_id INTEGER REFERENCES invites(id),
		screenshots TEXT NOT NULL DEFAULT 'none' CHECK (screenshots IN ('none','pending','approved','denied')),
		revoked INTEGER NOT NULL DEFAULT 0,
		last_seen INTEGER
	);
	CREATE TABLE claims (
		id INTEGER PRIMARY KEY,
		flavor TEXT NOT NULL,
		region TEXT NOT NULL,
		realm TEXT NOT NULL,
		name TEXT NOT NULL,
		guid TEXT NOT NULL,
		key_id INTEGER NOT NULL REFERENCES keys(id),
		created INTEGER NOT NULL,
		updated INTEGER NOT NULL,
		steps INTEGER NOT NULL,
		data_bytes INTEGER NOT NULL,
		shot_bytes INTEGER NOT NULL DEFAULT 0,
		UNIQUE(flavor, region, realm, name)
	);
	CREATE TABLE nonces (
		key_id INTEGER NOT NULL,
		nonce BLOB NOT NULL,
		seen INTEGER NOT NULL,
		PRIMARY KEY(key_id, nonce)
	);
	CREATE INDEX nonces_seen ON nonces(seen);
	CREATE INDEX claims_key ON claims(key_id);`,
	// shots holds one row for each stored screenshot. upload_sha256 is the hash of the bytes the client sent, which
	// is not the hash of the stored file, because the server encodes the image again.
	`CREATE TABLE shots (
		claim_id INTEGER NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
		file TEXT NOT NULL,
		upload_sha256 BLOB NOT NULL,
		bytes INTEGER NOT NULL,
		PRIMARY KEY(claim_id, file)
	);`,
}

func (s *Store) migrate(ctx context.Context) error {
	var have int
	if err := s.db.QueryRowContext(ctx, `PRAGMA user_version`).Scan(&have); err != nil {
		return err
	}
	if have > len(migrations) {
		return fmt.Errorf("the file has schema version %d, but this server knows up to %d. Run a newer server", have, len(migrations))
	}
	for v := have; v < len(migrations); v++ {
		err := s.inTx(ctx, func(tx *sql.Tx) error {
			if _, err := tx.ExecContext(ctx, migrations[v]); err != nil {
				return err
			}
			// PRAGMA takes no bound parameter; v is a loop counter, not input.
			_, err := tx.ExecContext(ctx, fmt.Sprintf(`PRAGMA user_version = %d`, v+1))
			return err
		})
		if err != nil {
			return fmt.Errorf("migration to schema version %d failed: %w", v+1, err)
		}
	}
	return nil
}
