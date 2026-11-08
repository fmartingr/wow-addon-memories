package store

import (
	"context"
	"database/sql"
	"errors"
)

// Shot is a stored screenshot of a claim.
type Shot struct {
	// UploadSHA256 is the hash of the bytes that the client sent.
	UploadSHA256 []byte
	// Bytes is the size of the stored file.
	Bytes int64
}

// ShotOf returns the stored screenshot row of the claim, or ErrNotFound.
func (s *Store) ShotOf(ctx context.Context, claimID int64, file string) (Shot, error) {
	var sh Shot
	err := s.db.QueryRowContext(ctx,
		`SELECT upload_sha256, bytes FROM shots WHERE claim_id = ? AND file = ?`, claimID, file).Scan(&sh.UploadSHA256, &sh.Bytes)
	if errors.Is(err, sql.ErrNoRows) {
		return Shot{}, ErrNotFound
	}
	return sh, err
}

// ShotBytesOfKey returns the sum of shot_bytes over the claims of the key.
func (s *Store) ShotBytesOfKey(ctx context.Context, keyID int64) (int64, error) {
	var n int64
	err := s.db.QueryRowContext(ctx,
		`SELECT COALESCE(SUM(shot_bytes), 0) FROM claims WHERE key_id = ?`, keyID).Scan(&n)
	return n, err
}

// SetShot records a stored screenshot and sets shot_bytes of the claim to the sum of its screenshots, in one
// transaction. It returns ErrNotFound when the claim does not exist.
func (s *Store) SetShot(ctx context.Context, claimID int64, file string, uploadSHA256 []byte, bytes int64) error {
	return s.inTx(ctx, func(tx *sql.Tx) error {
		// INSERT ... SELECT inserts no row for a claim that a delete removed, which is how a missing claim shows.
		res, err := tx.ExecContext(ctx,
			`INSERT INTO shots (claim_id, file, upload_sha256, bytes) SELECT id, ?, ?, ? FROM claims WHERE id = ?
			 ON CONFLICT(claim_id, file) DO UPDATE SET upload_sha256 = excluded.upload_sha256, bytes = excluded.bytes`,
			file, uploadSHA256, bytes, claimID)
		if err != nil {
			return err
		}
		if n, err := res.RowsAffected(); err != nil {
			return err
		} else if n == 0 {
			return ErrNotFound
		}
		_, err = tx.ExecContext(ctx,
			`UPDATE claims SET shot_bytes = (SELECT COALESCE(SUM(bytes), 0) FROM shots WHERE claim_id = ?1) WHERE id = ?1`, claimID)
		return err
	})
}
