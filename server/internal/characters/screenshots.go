package characters

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"path"

	"github.com/fmartingr/wow-addon-memories/server/internal/images"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

var (
	// ErrNotReferenced means that no stored record of the character names the screenshot.
	ErrNotReferenced = errors.New("characters: no stored record names this screenshot")
	// ErrShotQuota means that the screenshots of the key would go over its limit.
	ErrShotQuota = errors.New("characters: the key would hold too many screenshot bytes")
)

const shotPrefix = "screenshots/"

// ShotLimits are the limits of SaveScreenshot.
type ShotLimits struct {
	MaxPixels   int64
	MaxKeyBytes int64
}

// referenced reports whether a stored record of the claim names the screenshot. It streams journey.jsonl, the file
// that holds the records, and decodes only the screenshot field of each, so a check costs one record of memory and
// not a decode of the whole character. The key must be exactly "screenshot": a struct tag matches keys without
// regard to case, and a record of an unknown kind may carry a free-text "Screenshot" that the merge never strips.
func (s *Service) referenced(ctx context.Context, id int64, file string) (bool, error) {
	f, err := s.blobs.Open(ctx, blobPath(id, fileJourney))
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	defer f.Close()
	want := shotPrefix + file
	dec := json.NewDecoder(f)
	for {
		var r map[string]json.RawMessage
		err := dec.Decode(&r)
		if errors.Is(err, io.EOF) {
			return false, nil
		}
		if err != nil {
			return false, err
		}
		raw, ok := r["screenshot"]
		if !ok {
			continue
		}
		var got string
		if err := json.Unmarshal(raw, &got); err != nil {
			return false, err
		}
		if got == want {
			return true, nil
		}
	}
}

// SaveScreenshot stores a clean copy of a screenshot that a stored record of the character names. It holds the lock
// of the path, so a delete or a save cannot run in the middle of it, and it reads the stored journey under that lock.
// It returns false when the stored copy came from the same upload bytes, and then it writes nothing. A path that does
// not exist, or that another key owns, gives store.ErrNotFound. file must match the screenshot name pattern; an
// extension other than .jpg and .png gives images.ErrUnsupported.
func (s *Service) SaveScreenshot(ctx context.Context, key store.Key, p Path, file string, body []byte, lim ShotLimits) (bool, error) {
	unlock := s.locks.lock(p.String())
	defer unlock()

	claim, err := s.store.ClaimByPath(ctx, p.Flavor, p.Region, p.Realm, p.Name)
	if err != nil {
		return false, err
	}
	if claim.KeyID != key.ID {
		return false, store.ErrNotFound
	}
	ok, err := s.referenced(ctx, claim.ID, file)
	if err != nil {
		return false, err
	}
	if !ok {
		return false, ErrNotReferenced
	}

	sum := sha256.Sum256(body)
	blob := blobPath(claim.ID, shotPrefix+file)
	old, err := s.store.ShotOf(ctx, claim.ID, file)
	hadOld := err == nil
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		return false, err
	}
	if hadOld && bytes.Equal(old.UploadSHA256, sum[:]) {
		f, err := s.blobs.Open(ctx, blob)
		if err == nil {
			f.Close()
			return false, nil
		}
		if !errors.Is(err, fs.ErrNotExist) {
			return false, err
		}
		// The file is gone although the row says otherwise: store it again.
	}

	clean, err := images.Clean(body, path.Ext(file), lim.MaxPixels)
	if err != nil {
		return false, err
	}

	unlockKey := s.keys.lock(claimPrefix(key.ID))
	defer unlockKey()
	used, err := s.store.ShotBytesOfKey(ctx, key.ID)
	if err != nil {
		return false, err
	}
	if hadOld {
		used -= old.Bytes
	}
	if used+int64(len(clean)) > lim.MaxKeyBytes {
		return false, ErrShotQuota
	}
	if err := s.blobs.Write(ctx, blob, bytes.NewReader(clean)); err != nil {
		return false, err
	}
	if err := s.store.SetShot(ctx, claim.ID, file, sum[:], int64(len(clean))); err != nil {
		// The file goes in both cases: with no row it would count toward no quota, and with an old row its hash would
		// match the old upload, so a retry of that upload would keep the new file. A row without its file is stored
		// again by the next upload.
		if rmErr := s.blobs.Remove(context.WithoutCancel(ctx), blob); rmErr != nil {
			s.log.Error("could not remove a screenshot after a failed save", "claim", claim.ID, "err", rmErr.Error())
		}
		return false, err
	}
	return true, nil
}
