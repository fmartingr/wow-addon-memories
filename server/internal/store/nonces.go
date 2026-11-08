package store

import (
	"context"
	"time"
)

// NonceTTL is how long the server remembers a nonce. A request is signed for a 300 s window on each side of the
// server time, so a replay of a still-valid request is at most 600 s after the first use.
const NonceTTL = 600 * time.Second

// UseNonce records the nonce of the key. It returns false when the pair was already seen within NonceTTL.
func (s *Store) UseNonce(ctx context.Context, keyID int64, nonce []byte) (fresh bool, err error) {
	now := s.now().Unix()
	// A row older than NonceTTL that the purge has not removed yet counts as unseen.
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO nonces (key_id, nonce, seen) VALUES (?, ?, ?)
		 ON CONFLICT (key_id, nonce) DO UPDATE SET seen = excluded.seen WHERE nonces.seen < ?`,
		keyID, nonce, now, now-int64(NonceTTL/time.Second))
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	return n == 1, err
}

// NonceSeen reports whether the pair was seen within NonceTTL. It writes nothing, so a caller can reject a replay
// before it spends anything on the request; UseNonce stays the atomic check.
func (s *Store) NonceSeen(ctx context.Context, keyID int64, nonce []byte) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM nonces WHERE key_id = ? AND nonce = ? AND seen >= ?`,
		keyID, nonce, s.now().Unix()-int64(NonceTTL/time.Second)).Scan(&n)
	return n > 0, err
}

// PurgeNonces drops the nonces older than NonceTTL and returns how many it dropped.
func (s *Store) PurgeNonces(ctx context.Context) (int64, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM nonces WHERE seen < ?`, s.now().Unix()-int64(NonceTTL/time.Second))
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// PurgeLoop purges the nonces every interval until ctx ends.
func (s *Store) PurgeLoop(ctx context.Context, interval time.Duration, onError func(error)) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if _, err := s.PurgeNonces(ctx); err != nil && ctx.Err() == nil {
				onError(err)
			}
		}
	}
}
