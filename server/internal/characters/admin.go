package characters

import (
	"bytes"
	"context"
	"errors"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
	"github.com/fmartingr/wow-addon-memories/server/internal/merge"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// ErrAlreadyOwner means that the target key of a move owns the path already.
var ErrAlreadyOwner = errors.New("characters: the key owns the path already")

// Move gives the character at p to another key. It holds the lock of the path, so it cannot run in the middle of a
// save or a delete of the same path. The target must exist and not be revoked (see store.MoveClaim); a target that
// owns the path already gives ErrAlreadyOwner.
func (s *Service) Move(ctx context.Context, p Path, toKey int64) error {
	unlock := s.locks.lock(p.String())
	defer unlock()
	claim, err := s.store.ClaimByPath(ctx, p.Flavor, p.Region, p.Realm, p.Name)
	if err != nil {
		return err
	}
	if claim.KeyID == toKey {
		return ErrAlreadyOwner
	}
	return s.store.MoveClaim(ctx, claim.ID, toKey)
}

// StripScreenshots removes the screenshot field from the stored records of every character of the key, deletes the
// screenshot files and their rows, and sets shot_bytes to 0. It returns how many characters it cleaned. A failed
// character does not stop the others, so one damaged character cannot keep the files of the rest online; the error
// joins every failure. Running it again finishes the work, because each step skips what is already done.
// The records change before the files go, so a stop in the middle never leaves a record that names a file the page
// can still serve after the admin revoked it.
func (s *Service) StripScreenshots(ctx context.Context, keyID int64) (int, error) {
	claims, err := s.store.ClaimsOfKey(ctx, keyID)
	if err != nil {
		return 0, err
	}
	n := 0
	var errs []error
	for _, c := range claims {
		stripped, err := s.stripClaim(ctx, Path{c.Flavor, c.Region, c.Realm, c.Name}, keyID)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		if stripped {
			n++
		}
	}
	return n, errors.Join(errs...)
}

// stripClaim cleans one character of the key. It returns false when the path is gone or belongs to another key.
func (s *Service) stripClaim(ctx context.Context, p Path, keyID int64) (bool, error) {
	unlock := s.locks.lock(p.String())
	defer unlock()
	// The claim is read again under the lock: a delete or a move may have changed it since the list.
	claim, err := s.store.ClaimByPath(ctx, p.Flavor, p.Region, p.Realm, p.Name)
	if errors.Is(err, store.ErrNotFound) || (err == nil && claim.KeyID != keyID) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, s.stripFiles(ctx, claim, p)
}

func (s *Service) stripFiles(ctx context.Context, claim store.Claim, p Path) error {
	up, raw, err := s.load(ctx, claim.ID)
	if err != nil {
		// Stored data that does not load cannot lose its screenshot fields, but its images must still go offline.
		return errors.Join(err, s.removeShots(ctx, claim.ID))
	}
	if up != nil {
		changed := false
		for _, r := range up.Records {
			if _, ok := r["screenshot"]; ok {
				delete(r, "screenshot")
				changed = true
			}
		}
		if changed {
			journey, err := up.JourneyJSONL()
			if err != nil {
				return err
			}
			entry, err := jsonw.Marshal(merge.Entry(p.String(), up), true)
			if err != nil {
				return err
			}
			// The journey goes last: a retry redoes this block only while the journey still has screenshot fields, so
			// every step before it must be repeatable and done by the time the journey changes.
			if err := s.blobs.Write(ctx, blobPath(claim.ID, fileEntry), bytes.NewReader(entry)); err != nil {
				return err
			}
			total := int64(len(journey) + len(entry) + len(raw[fileCharacter]) + len(raw[fileTrail]))
			if err := s.store.SetClaimData(ctx, claim.ID, int64(len(up.Records)), total); err != nil {
				return err
			}
			if err := s.blobs.Write(ctx, blobPath(claim.ID, fileJourney), bytes.NewReader(journey)); err != nil {
				return err
			}
		}
	}
	return s.removeShots(ctx, claim.ID)
}

func (s *Service) removeShots(ctx context.Context, claimID int64) error {
	if err := s.blobs.RemoveAll(ctx, claimPrefix(claimID)+shotDirName); err != nil {
		return err
	}
	return s.store.ClearShots(ctx, claimID)
}

const shotDirName = "screenshots"
