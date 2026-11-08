// Package characters stores and deletes the characters of the keys: the claim row, the files and the lock that
// orders the two. Every change to a character goes through it, so all of them share one lock per path.
package characters

import (
	"bytes"
	"context"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"strconv"
	"sync"

	"github.com/fmartingr/wow-addon-memories/server/internal/jsonw"
	"github.com/fmartingr/wow-addon-memories/server/internal/merge"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

var (
	// ErrClaimed means that another key owns the path.
	ErrClaimed = errors.New("characters: another key owns the path")
	// ErrGUIDMismatch means that the key owns the path for a character with another GUID.
	ErrGUIDMismatch = errors.New("characters: the path belongs to a character with another GUID")
	// ErrCharacterQuota means that the key owns the most characters that it may.
	ErrCharacterQuota = errors.New("characters: the key owns too many characters")
	// ErrDataQuota means that the data of the key would go over its limit.
	ErrDataQuota = errors.New("characters: the key would hold too much data")
	// ErrCharacterTooLarge means that the stored files of the character would go over the limit of one character.
	ErrCharacterTooLarge = errors.New("characters: the character would be too large")
)

// The data files of a claim, in the order that Save writes them: entry.json goes last, because it is what a page
// reads first.
const (
	fileCharacter = "character.json"
	fileJourney   = "journey.jsonl"
	fileTrail     = "trail.jsonl"
	fileEntry     = "entry.json"
)

var dataFiles = []string{fileJourney, fileTrail, fileCharacter, fileEntry}

// Path is the address of a character: <flavor>/<region>/<realm>/<name>.
type Path struct{ Flavor, Region, Realm, Name string }

func (p Path) String() string { return p.Flavor + "/" + p.Region + "/" + p.Realm + "/" + p.Name }

// Quotas are the limits that Save keeps for one key.
type Quotas struct {
	MaxCharacters int64
	MaxDataBytes  int64
	// MaxCharacterBytes caps the stored files of one character. Every save loads and decodes them, so this bound,
	// and not the data quota of the key, sets the memory of a save.
	MaxCharacterBytes int64
}

// Result is the outcome of a Save.
type Result struct {
	Path  string
	Steps int64
	// Added is the number of records that the upload added to the stored ones.
	Added int64
}

// Service keeps the claims and the files of the characters.
type Service struct {
	store *store.Store
	blobs store.Blobs
	log   *slog.Logger
	locks pathLocks
	// keys orders the data quota check and the write of the saves of one key, so two paths of one key saved at
	// the same time cannot both pass the check. A save takes its key lock while it holds its path lock.
	keys pathLocks
}

// New returns a Service over the store and the blobs.
func New(st *store.Store, blobs store.Blobs, log *slog.Logger) *Service {
	return &Service{
		store: st, blobs: blobs, log: log,
		locks: pathLocks{m: map[string]*pathLock{}},
		keys:  pathLocks{m: map[string]*pathLock{}},
	}
}

// pathLocks holds one mutex for each path in use, and forgets it when the last user leaves, so the map does not
// grow with the paths that were ever tried.
type pathLocks struct {
	mu sync.Mutex
	m  map[string]*pathLock
}

type pathLock struct {
	mu   sync.Mutex
	refs int
}

func (l *pathLocks) lock(path string) (unlock func()) {
	l.mu.Lock()
	pl := l.m[path]
	if pl == nil {
		pl = &pathLock{}
		l.m[path] = pl
	}
	pl.refs++
	l.mu.Unlock()
	pl.mu.Lock()
	return func() {
		pl.mu.Unlock()
		l.mu.Lock()
		if pl.refs--; pl.refs == 0 {
			delete(l.m, path)
		}
		l.mu.Unlock()
	}
}

func claimPrefix(id int64) string { return strconv.FormatInt(id, 10) + "/" }

func blobPath(id int64, name string) string { return claimPrefix(id) + name }

// Save merges the upload into the stored data of its path and writes the files. The first key to save a path owns it
// from then on. The files and the claim change together: when the save fails, the old files stay, and a claim made
// by this save goes away. up must come from validate.Read, so its path parts are safe.
func (s *Service) Save(ctx context.Context, key store.Key, up *validate.Upload, q Quotas) (Result, error) {
	path := Path{up.Flavor, up.Region, up.Realm, up.Name}
	unlock := s.locks.lock(path.String())
	defer unlock()

	guid, _ := up.Character["guid"].(string)
	claim, err := s.store.ClaimByPath(ctx, path.Flavor, path.Region, path.Realm, path.Name)
	created := false
	switch {
	case errors.Is(err, store.ErrNotFound):
		id, err := s.store.CreateClaimWithin(ctx, store.Claim{
			Flavor: path.Flavor, Region: path.Region, Realm: path.Realm, Name: path.Name, GUID: guid, KeyID: key.ID,
		}, q.MaxCharacters)
		if errors.Is(err, store.ErrClaimQuota) {
			return Result{}, ErrCharacterQuota
		}
		if err != nil {
			return Result{}, err
		}
		claim = store.Claim{ID: id, KeyID: key.ID, GUID: guid}
		created = true
	case err != nil:
		return Result{}, err
	case claim.KeyID != key.ID:
		return Result{}, ErrClaimed
	case claim.GUID != guid:
		return Result{}, ErrGUIDMismatch
	}

	res, err := s.write(ctx, claim, key, path, up, q)
	if err != nil && created {
		// The request may be gone already; the cleanup must still run, or an empty claim would block the path.
		s.discard(context.WithoutCancel(ctx), claim.ID)
	}
	return res, err
}

func (s *Service) write(ctx context.Context, claim store.Claim, key store.Key, path Path, up *validate.Upload, q Quotas) (res Result, err error) {
	if claim.DataBytes > q.MaxCharacterBytes {
		return Result{}, ErrCharacterTooLarge
	}
	old, oldRaw, err := s.load(ctx, claim.ID)
	if err != nil {
		return Result{}, err
	}
	var oldSteps int64
	if old != nil {
		oldSteps = int64(len(old.Records))
	}
	// old is not used after the merge, so the decoded stored data can be freed while the files are written.
	merged := merge.Character(old, up, key.Screenshots == store.ShotsApproved)

	entry, err := jsonw.Marshal(merge.Entry(path.String(), merged), true)
	if err != nil {
		return Result{}, err
	}
	character, err := merged.CharacterJSON()
	if err != nil {
		return Result{}, err
	}
	journey, err := merged.JourneyJSONL()
	if err != nil {
		return Result{}, err
	}
	trail, err := merged.TrailJSONL()
	if err != nil {
		return Result{}, err
	}
	out := map[string][]byte{fileEntry: entry, fileCharacter: character, fileJourney: journey, fileTrail: trail}
	total := int64(len(entry) + len(character) + len(journey) + len(trail))
	if total > q.MaxCharacterBytes {
		return Result{}, ErrCharacterTooLarge
	}

	unlockKey := s.keys.lock(claimPrefix(key.ID))
	defer unlockKey()
	// The check comes before the first write, so a refusal leaves every old file as it was.
	others, err := s.store.DataBytesOfKey(ctx, key.ID, claim.ID)
	if err != nil {
		return Result{}, err
	}
	if others+total > q.MaxDataBytes {
		return Result{}, ErrDataQuota
	}

	var written []string
	defer func() {
		if err != nil {
			s.restore(context.WithoutCancel(ctx), claim.ID, written, oldRaw)
		}
	}()
	for _, name := range dataFiles {
		if err = s.blobs.Write(ctx, blobPath(claim.ID, name), bytes.NewReader(out[name])); err != nil {
			return Result{}, err
		}
		written = append(written, name)
	}
	steps := int64(len(merged.Records))
	if err = s.store.SetClaimData(ctx, claim.ID, steps, total); err != nil {
		return Result{}, err
	}
	// A merge can drop an sn record whose note it carried onto an ss, so the count can shrink.
	return Result{Path: path.String(), Steps: steps, Added: max(0, steps-oldSteps)}, nil
}

// restore puts the old bytes back in each file that a failed save wrote, and removes the files that did not exist.
// It is best effort: a second failure leaves a mixed state that the next upload of the owner repairs.
func (s *Service) restore(ctx context.Context, id int64, written []string, oldRaw map[string][]byte) {
	for _, name := range written {
		var err error
		if b, ok := oldRaw[name]; ok {
			err = s.blobs.Write(ctx, blobPath(id, name), bytes.NewReader(b))
		} else {
			err = s.blobs.Remove(ctx, blobPath(id, name))
		}
		if err != nil {
			s.log.Error("could not restore a stored file after a failed save", "claim", id, "file", name, "err", err.Error())
		}
	}
}

// discard removes the files and then the row of a claim that a failed first save made.
func (s *Service) discard(ctx context.Context, id int64) {
	if err := s.blobs.RemoveAll(ctx, claimPrefix(id)); err != nil {
		// The row stays with its files: SQLite gives a deleted top id to the next claim, which would load them. The
		// next save of the owner adopts the claim.
		s.log.Error("could not remove the files of a failed first save", "claim", id, "err", err.Error())
		return
	}
	if err := s.store.DeleteClaim(ctx, id); err != nil {
		s.log.Error("could not remove the claim of a failed first save", "claim", id, "err", err.Error())
	}
}

// load reads the stored files of a claim. It returns a nil upload when the claim has no character.json yet, and
// the raw bytes of each file that exists.
func (s *Service) load(ctx context.Context, id int64) (*validate.Upload, map[string][]byte, error) {
	raw := map[string][]byte{}
	for _, name := range dataFiles {
		b, err := s.read(ctx, blobPath(id, name))
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, nil, err
		}
		raw[name] = b
	}
	if _, ok := raw[fileCharacter]; !ok {
		return nil, raw, nil
	}
	up, err := validate.ReadStored(raw[fileCharacter], raw[fileJourney], raw[fileTrail], s.store.Now())
	if err != nil {
		return nil, nil, err
	}
	return up, raw, nil
}

// Load returns the stored data of a claim, or nil when it has none.
func (s *Service) Load(ctx context.Context, id int64) (*validate.Upload, error) {
	up, _, err := s.load(ctx, id)
	return up, err
}

func (s *Service) read(ctx context.Context, path string) ([]byte, error) {
	f, err := s.blobs.Open(ctx, path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(f)
}

// Delete removes the files of the character and then its claim, so a failed delete leaves a claim that the caller can
// delete again. A key of owner other than 0 can delete only its own character; 0 means any owner, for the admin.
// A missing path, and a path of another owner, both give store.ErrNotFound.
func (s *Service) Delete(ctx context.Context, p Path, owner int64) error {
	unlock := s.locks.lock(p.String())
	defer unlock()
	claim, err := s.store.ClaimByPath(ctx, p.Flavor, p.Region, p.Realm, p.Name)
	if err != nil {
		return err
	}
	if owner != 0 && claim.KeyID != owner {
		return store.ErrNotFound
	}
	if err := s.blobs.RemoveAll(ctx, claimPrefix(claim.ID)); err != nil {
		return err
	}
	return s.store.DeleteClaim(ctx, claim.ID)
}

// DeleteAllOfKey deletes every character of the key and returns how many it deleted. It stops at the first failure.
func (s *Service) DeleteAllOfKey(ctx context.Context, keyID int64) (int, error) {
	claims, err := s.store.ClaimsOfKey(ctx, keyID)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, c := range claims {
		err := s.Delete(ctx, Path{c.Flavor, c.Region, c.Realm, c.Name}, keyID)
		if errors.Is(err, store.ErrNotFound) {
			continue
		}
		if err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}
