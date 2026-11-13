package store

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

var ctx = context.Background()

type fakeClock struct{ t time.Time }

func (c *fakeClock) Now() time.Time          { return c.t }
func (c *fakeClock) Advance(d time.Duration) { c.t = c.t.Add(d) }

func openTest(t *testing.T) (*Store, *fakeClock) {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	clock := &fakeClock{t: time.Unix(1794000000, 0)}
	s.SetClock(clock.Now)
	return s, clock
}

func pubKey(n byte) []byte { return bytes.Repeat([]byte{n}, 32) }

func nonce(n byte) []byte { return bytes.Repeat([]byte{n}, 16) }

func register(t *testing.T, s *Store, pub []byte, invite string) (bool, error) {
	t.Helper()
	return s.Register(ctx, RegisterInput{Public: pub, Nonce: nonce(pub[0]), Invite: invite})
}

// registerInvited registers pub with a new invite, so the key is not an open key.
func registerInvited(t *testing.T, s *Store, pub []byte) {
	t.Helper()
	_, code, err := s.CreateInvite(ctx, "", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := register(t, s, pub, code); err != nil {
		t.Fatal(err)
	}
}

func mustKey(t *testing.T, s *Store, pub []byte) Key {
	t.Helper()
	k, err := s.KeyByPublic(ctx, pub)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func TestOpenMigratesAnEmptyFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "memories.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	var version int
	if err := s.db.QueryRow(`PRAGMA user_version`).Scan(&version); err != nil || version != len(migrations) {
		t.Fatalf("user_version = %d, %v; want %d", version, err, len(migrations))
	}
	var journal string
	s.db.QueryRow(`PRAGMA journal_mode`).Scan(&journal)
	var fk int
	s.db.QueryRow(`PRAGMA foreign_keys`).Scan(&fk)
	if journal != "wal" || fk != 1 {
		t.Errorf("journal_mode = %q, foreign_keys = %d; want wal and 1", journal, fk)
	}
	for _, table := range []string{"keys", "invites", "claims", "nonces", "shots"} {
		if _, err := s.db.Exec(`SELECT 1 FROM ` + table); err != nil {
			t.Errorf("table %s: %v", table, err)
		}
	}
	if _, err := s.db.Exec(`INSERT INTO keys (public_key, created, screenshots) VALUES (x'00', 1, 'maybe')`); err == nil {
		t.Error("the screenshots CHECK accepted an unknown state")
	}
	if _, err := s.db.Exec(`INSERT INTO claims (flavor, region, realm, name, guid, key_id, created, updated, steps, data_bytes)
		VALUES ('wow', 'eu', 'r', 'n', 'g', 99, 1, 1, 0, 0)`); err == nil {
		t.Error("foreign keys accepted a claim of a missing key")
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}

	s, err = Open(path)
	if err != nil {
		t.Fatalf("a second Open: %v", err)
	}
	s.Close()
}

func TestOpenCreatesThePrivateFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "memories.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for _, p := range []string{path, path + "-wal"} {
		if info, err := os.Stat(p); err != nil || info.Mode().Perm() != 0o600 {
			t.Errorf("%s: mode %v, %v; want 0600", filepath.Base(p), info.Mode().Perm(), err)
		}
	}
}

func TestOpenRefusesANewerSchema(t *testing.T) {
	path := filepath.Join(t.TempDir(), "memories.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`PRAGMA user_version = 99`); err != nil {
		t.Fatal(err)
	}
	s.Close()
	if _, err := Open(path); err == nil || !strings.Contains(err.Error(), "Run a newer server") {
		t.Errorf("Open = %v, want the newer-schema error", err)
	}
}

func TestOpenFailsOnAFileThatIsNotADatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "memories.db")
	if err := os.WriteFile(path, []byte(strings.Repeat("not a database ", 100)), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(path); err == nil || !strings.Contains(err.Error(), path) {
		t.Errorf("Open = %v, want an error that names the file", err)
	}
}

func TestOpenKeepsSpecialCharactersOfThePath(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "a?b#c d")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	s, err := Open(filepath.Join(dir, "memories.db"))
	if err != nil {
		t.Fatal(err)
	}
	s.Close()
	if _, err := os.Stat(filepath.Join(dir, "memories.db")); err != nil {
		t.Errorf("the database is not in the folder: %v", err)
	}
}

func TestRegisterWithAnInvite(t *testing.T) {
	s, _ := openTest(t)
	_, code, err := s.CreateInvite(ctx, "friend", 30*24*time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if len(code) != 16 || strings.Trim(code, crockford) != "" {
		t.Fatalf("code = %q, want 16 Crockford base32 characters", code)
	}
	created, err := register(t, s, pubKey(1), code)
	if err != nil || !created {
		t.Fatalf("Register = %v, %v; want created", created, err)
	}
	k := mustKey(t, s, pubKey(1))
	if k.Screenshots != ShotsNone || k.Revoked || k.Created != s.Now().Unix() {
		t.Errorf("key = %+v", k)
	}
	var inviteID, usedBy, nonces int64
	s.db.QueryRow(`SELECT invite_id FROM keys WHERE id = ?`, k.ID).Scan(&inviteID)
	s.db.QueryRow(`SELECT used_by FROM invites WHERE id = ?`, inviteID).Scan(&usedBy)
	s.db.QueryRow(`SELECT COUNT(*) FROM nonces WHERE key_id = ?`, k.ID).Scan(&nonces)
	if usedBy != k.ID || nonces != 1 {
		t.Errorf("invite used_by = %d (key %d), nonces = %d", usedBy, k.ID, nonces)
	}

	if created, err := register(t, s, pubKey(1), "wrong"); err != nil || created {
		t.Errorf("a second registration of the key = %v, %v; want created false", created, err)
	}
	if _, err := register(t, s, pubKey(2), code); !errors.Is(err, ErrInviteInvalid) {
		t.Errorf("a used code = %v, want ErrInviteInvalid", err)
	}
	if _, err := s.KeyByPublic(ctx, pubKey(2)); !errors.Is(err, ErrNotFound) {
		t.Errorf("the key of a failed registration exists: %v", err)
	}
}

func TestInviteNeverStoredInClear(t *testing.T) {
	s, _ := openTest(t)
	_, code, _ := s.CreateInvite(ctx, "", time.Hour)
	var n int
	s.db.QueryRow(`SELECT COUNT(*) FROM invites WHERE CAST(code_hash AS TEXT) LIKE '%' || ? || '%'`, code).Scan(&n)
	if n != 0 {
		t.Error("the invite code is in the table in clear text")
	}
	var size int
	s.db.QueryRow(`SELECT length(code_hash) FROM invites`).Scan(&size)
	if size != 32 {
		t.Errorf("code_hash has %d bytes, want a SHA-256", size)
	}
}

func TestInviteCodeIsNormalized(t *testing.T) {
	s, _ := openTest(t)
	// Build a code with characters that have a look-alike.
	for {
		_, code, _ := s.CreateInvite(ctx, "", time.Hour)
		if strings.ContainsAny(code, "01") {
			typed := strings.ToLower(code[:4] + "-" + code[4:8] + " " + code[8:])
			typed = strings.NewReplacer("0", "o", "1", "l").Replace(typed)
			if created, err := register(t, s, pubKey(1), typed); err != nil || !created {
				t.Fatalf("Register with %q for %q = %v, %v", typed, code, created, err)
			}
			return
		}
	}
}

func TestInviteValidity(t *testing.T) {
	s, clock := openTest(t)
	_, expired, _ := s.CreateInvite(ctx, "", time.Hour)
	_, atLimit, _ := s.CreateInvite(ctx, "", time.Hour)
	revokedID, revoked, _ := s.CreateInvite(ctx, "", time.Hour)
	if err := s.RevokeInvite(ctx, revokedID); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Hour - time.Second)
	if _, err := register(t, s, pubKey(1), atLimit); err != nil {
		t.Errorf("a code one second before it ends: %v", err)
	}
	clock.Advance(time.Second)
	for name, code := range map[string]string{"expired": expired, "revoked": revoked, "unknown": "0123456789ABCDEF", "empty": "", "short": "ABC", "bad characters": "UUUUUUUUUUUUUUUU"} {
		if _, err := register(t, s, pubKey(9), code); !errors.Is(err, ErrInviteInvalid) {
			t.Errorf("%s code: %v, want ErrInviteInvalid", name, err)
		}
	}
	if err := s.RevokeInvite(ctx, 12345); !errors.Is(err, ErrNotFound) {
		t.Errorf("RevokeInvite of a missing id = %v", err)
	}
}

func TestRegisterOpen(t *testing.T) {
	s, _ := openTest(t)
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1)}); !errors.Is(err, ErrInviteInvalid) {
		t.Errorf("registration with no invite and no open registration = %v", err)
	}
	if created, err := s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1), AllowOpen: true}); err != nil || !created {
		t.Fatalf("open registration = %v, %v", created, err)
	}
	if !mustKey(t, s, pubKey(1)).Open {
		t.Error("a key with no invite is not an open key")
	}
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(2), Nonce: nonce(2), Invite: "garbage", AllowOpen: true}); err != nil {
		t.Errorf("open registration with a bad code = %v", err)
	}
	_, used, _ := s.CreateInvite(ctx, "", time.Hour)
	registerInvited(t, s, pubKey(5))
	register(t, s, pubKey(6), used)
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(7), Nonce: nonce(7), Invite: used, AllowOpen: true}); err != nil {
		t.Errorf("open registration with a used code = %v", err)
	}
	for _, n := range []byte{2, 7} {
		if !mustKey(t, s, pubKey(n)).Open {
			t.Errorf("key %d with a code that does not work is not an open key", n)
		}
	}
	_, code, _ := s.CreateInvite(ctx, "", time.Hour)
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(3), Nonce: nonce(3), Invite: code, AllowOpen: true}); err != nil {
		t.Fatal(err)
	}
	if mustKey(t, s, pubKey(3)).Open {
		t.Error("a key with an invite is an open key")
	}
	// A registered open key registers again after open registration closes.
	if created, err := s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(4)}); err != nil || created {
		t.Errorf("a second registration of an open key = %v, %v", created, err)
	}
}

func TestOpenKeyCannotAskForScreenshots(t *testing.T) {
	s, _ := openTest(t)
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1), AllowOpen: true})
	k := mustKey(t, s, pubKey(1))
	if state, err := s.RequestScreenshots(ctx, k.ID); err != nil || state != ShotsNone {
		t.Errorf("request of an open key = %q, %v; want none", state, err)
	}
}

func TestOpenSettings(t *testing.T) {
	s, _ := openTest(t)
	if o, err := s.OpenSettings(ctx); err != nil || o != DefaultOpenSettings() {
		t.Fatalf("settings before any save = %+v, %v", o, err)
	}
	if err := s.SeedOpen(ctx, true); err != nil {
		t.Fatal(err)
	}
	if err := s.SeedOpen(ctx, false); err != nil {
		t.Fatal(err)
	}
	if o, _ := s.OpenSettings(ctx); !o.Open {
		t.Error("a second seed changed the switch")
	}
	want := OpenSettings{Open: true, MaxDataBytes: 1000, MinFreePercent: 25}
	if err := s.SetOpenSettings(ctx, want); err != nil {
		t.Fatal(err)
	}
	if o, err := s.OpenSettings(ctx); err != nil || o != want {
		t.Errorf("settings = %+v, %v; want %+v", o, err, want)
	}
	if closed, err := s.CloseOpen(ctx); !closed || err != nil {
		t.Errorf("CloseOpen = %v, %v", closed, err)
	}
	if closed, err := s.CloseOpen(ctx); closed || err != nil {
		t.Errorf("a second CloseOpen = %v, %v", closed, err)
	}
	if o, _ := s.OpenSettings(ctx); o.Open || o.MaxDataBytes != 1000 {
		t.Errorf("settings after CloseOpen = %+v", o)
	}
}

func TestRevokedKeyKeepsTheInviteUnused(t *testing.T) {
	s, _ := openTest(t)
	_, first, _ := s.CreateInvite(ctx, "", time.Hour)
	if _, err := register(t, s, pubKey(1), first); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`UPDATE keys SET revoked = 1`); err != nil {
		t.Fatal(err)
	}
	_, second, _ := s.CreateInvite(ctx, "", time.Hour)
	if _, err := register(t, s, pubKey(1), second); !errors.Is(err, ErrKeyRevoked) {
		t.Fatalf("Register of a revoked key = %v, want ErrKeyRevoked", err)
	}
	if created, err := register(t, s, pubKey(2), second); err != nil || !created {
		t.Errorf("the invite of the revoked key's attempt is spent: %v, %v", created, err)
	}
}

func TestRegisterRaceSpendsACodeOnce(t *testing.T) {
	s, _ := openTest(t)
	_, code, _ := s.CreateInvite(ctx, "", time.Hour)
	const n = 8
	results := make(chan error, n)
	var wg sync.WaitGroup
	for i := range n {
		wg.Go(func() {
			_, err := register(t, s, pubKey(byte(i+1)), code)
			results <- err
		})
	}
	wg.Wait()
	close(results)
	wins, losses := 0, 0
	for err := range results {
		switch {
		case err == nil:
			wins++
		case errors.Is(err, ErrInviteInvalid):
			losses++
		default:
			t.Errorf("unexpected error: %v", err)
		}
	}
	if wins != 1 || losses != n-1 {
		t.Errorf("wins = %d, losses = %d; want 1 and %d", wins, losses, n-1)
	}
	var keys int
	s.db.QueryRow(`SELECT COUNT(*) FROM keys`).Scan(&keys)
	if keys != 1 {
		t.Errorf("%d keys exist, want 1", keys)
	}
}

func TestRegisterTheSameKeyTwiceAtOnce(t *testing.T) {
	s, _ := openTest(t)
	var wg sync.WaitGroup
	var mu sync.Mutex
	created := 0
	for range 6 {
		wg.Go(func() {
			c, err := s.Register(ctx, RegisterInput{Public: pubKey(5), Nonce: nonce(5), AllowOpen: true})
			if err != nil {
				t.Error(err)
			}
			if c {
				mu.Lock()
				created++
				mu.Unlock()
			}
		})
	}
	wg.Wait()
	if created != 1 {
		t.Errorf("%d registrations created the key, want 1", created)
	}
}

func TestNonces(t *testing.T) {
	s, clock := openTest(t)
	for id := range 2 {
		if _, err := s.Register(ctx, RegisterInput{Public: pubKey(byte(id + 1)), Nonce: nonce(0xee), AllowOpen: true}); err != nil {
			t.Fatal(err)
		}
	}
	a, b := mustKey(t, s, pubKey(1)), mustKey(t, s, pubKey(2))

	if fresh, err := s.UseNonce(ctx, a.ID, nonce(1)); err != nil || !fresh {
		t.Fatalf("first use = %v, %v", fresh, err)
	}
	if fresh, _ := s.UseNonce(ctx, a.ID, nonce(1)); fresh {
		t.Error("a repeated nonce was accepted")
	}
	if fresh, _ := s.UseNonce(ctx, b.ID, nonce(1)); !fresh {
		t.Error("a nonce of another key was refused")
	}

	clock.Advance(NonceTTL - time.Second)
	if fresh, _ := s.UseNonce(ctx, a.ID, nonce(1)); fresh {
		t.Error("a nonce inside the memory window was accepted")
	}
	clock.Advance(2 * time.Second)
	if n, err := s.PurgeNonces(ctx); err != nil || n < 2 {
		t.Errorf("PurgeNonces = %d, %v; want at least the 2 old rows", n, err)
	}
	if fresh, _ := s.UseNonce(ctx, a.ID, nonce(1)); !fresh {
		t.Error("a nonce older than the window was refused after the purge")
	}
}

func TestNonceSeen(t *testing.T) {
	s, clock := openTest(t)
	for id := range 2 {
		if _, err := s.Register(ctx, RegisterInput{Public: pubKey(byte(id + 1)), Nonce: nonce(0xee), AllowOpen: true}); err != nil {
			t.Fatal(err)
		}
	}
	a, b := mustKey(t, s, pubKey(1)), mustKey(t, s, pubKey(2))
	if seen, err := s.NonceSeen(ctx, a.ID, nonce(1)); err != nil || seen {
		t.Fatalf("a new nonce = %v, %v; want unseen", seen, err)
	}
	if seen, _ := s.NonceSeen(ctx, a.ID, nonce(1)); seen {
		t.Error("NonceSeen recorded the nonce")
	}
	s.UseNonce(ctx, a.ID, nonce(1))
	if seen, _ := s.NonceSeen(ctx, a.ID, nonce(1)); !seen {
		t.Error("a used nonce is unseen")
	}
	if seen, _ := s.NonceSeen(ctx, b.ID, nonce(1)); seen {
		t.Error("the nonce of another key counts as seen")
	}
	clock.Advance(NonceTTL + time.Second)
	if seen, _ := s.NonceSeen(ctx, a.ID, nonce(1)); seen {
		t.Error("a nonce older than the window counts as seen")
	}
}

func TestStaleNonceRowCountsAsUnseenBeforeThePurge(t *testing.T) {
	s, clock := openTest(t)
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(0xee), AllowOpen: true})
	k := mustKey(t, s, pubKey(1))
	s.UseNonce(ctx, k.ID, nonce(1))
	clock.Advance(NonceTTL + time.Second)
	if fresh, err := s.UseNonce(ctx, k.ID, nonce(1)); err != nil || !fresh {
		t.Errorf("a stale row = %v, %v; want fresh", fresh, err)
	}
	if fresh, _ := s.UseNonce(ctx, k.ID, nonce(1)); fresh {
		t.Error("the refreshed row was accepted twice")
	}
}

func TestNoncesSurviveARestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "memories.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(0xee), AllowOpen: true})
	k := mustKey(t, s, pubKey(1))
	s.UseNonce(ctx, k.ID, nonce(7))
	s.Close()

	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if fresh, _ := s.UseNonce(ctx, k.ID, nonce(7)); fresh {
		t.Error("a nonce was forgotten after a restart")
	}
}

func TestPurgeLoop(t *testing.T) {
	s, clock := openTest(t)
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1), AllowOpen: true})
	clock.Advance(NonceTTL + time.Second)

	loopCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		s.PurgeLoop(loopCtx, 5*time.Millisecond, func(err error) { t.Error(err) })
		close(done)
	}()
	deadline := time.Now().Add(5 * time.Second)
	for {
		var n int
		s.db.QueryRow(`SELECT COUNT(*) FROM nonces`).Scan(&n)
		if n == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the purge loop did not drop the old nonce")
		}
		time.Sleep(5 * time.Millisecond)
	}
	cancel()
	<-done
}

func TestPurgeLoopReportsErrors(t *testing.T) {
	s, _ := openTest(t)
	s.db.Close()
	got := make(chan error, 1)
	loopCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	go s.PurgeLoop(loopCtx, 5*time.Millisecond, func(err error) {
		select {
		case got <- err:
		default:
		}
	})
	select {
	case <-got:
	case <-time.After(5 * time.Second):
		t.Fatal("the error of a failed purge was not reported")
	}
}

func TestRequestScreenshots(t *testing.T) {
	s, _ := openTest(t)
	registerInvited(t, s, pubKey(1))
	k := mustKey(t, s, pubKey(1))
	for _, tc := range []struct{ from, want string }{
		{ShotsNone, ShotsPending},
		{ShotsPending, ShotsPending},
		{ShotsApproved, ShotsApproved},
		{ShotsDenied, ShotsPending},
	} {
		if _, err := s.db.Exec(`UPDATE keys SET screenshots = ? WHERE id = ?`, tc.from, k.ID); err != nil {
			t.Fatal(err)
		}
		got, err := s.RequestScreenshots(ctx, k.ID)
		if err != nil || got != tc.want {
			t.Errorf("from %s: %q, %v; want %q", tc.from, got, err, tc.want)
		}
	}
	if _, err := s.RequestScreenshots(ctx, 999); !errors.Is(err, ErrNotFound) {
		t.Errorf("a missing key = %v, want ErrNotFound", err)
	}
}

func TestTouchKey(t *testing.T) {
	s, clock := openTest(t)
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1), AllowOpen: true})
	k := mustKey(t, s, pubKey(1))
	clock.Advance(90 * time.Second)
	if err := s.TouchKey(ctx, k.ID); err != nil {
		t.Fatal(err)
	}
	if got := mustKey(t, s, pubKey(1)).LastSeen; got != clock.Now().Unix() {
		t.Errorf("LastSeen = %d, want %d", got, clock.Now().Unix())
	}
}

func TestClaims(t *testing.T) {
	s, _ := openTest(t)
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1), AllowOpen: true})
	s.Register(ctx, RegisterInput{Public: pubKey(2), Nonce: nonce(2), AllowOpen: true})
	a, b := mustKey(t, s, pubKey(1)), mustKey(t, s, pubKey(2))

	for _, c := range []Claim{
		{Flavor: "wow", Region: "eu", Realm: "zul", Name: "bob", GUID: "Player-1-00000001", KeyID: a.ID, Steps: 3, DataBytes: 10},
		{Flavor: "wow", Region: "eu", Realm: "brumamar", Name: "nandu", GUID: "Player-1-00000002", KeyID: a.ID},
		{Flavor: "wow", Region: "us", Realm: "x", Name: "y", GUID: "Player-1-00000003", KeyID: b.ID},
	} {
		if _, err := s.CreateClaim(ctx, c); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.ClaimsOfKey(ctx, a.ID)
	if err != nil || len(got) != 2 {
		t.Fatalf("ClaimsOfKey = %v, %v", got, err)
	}
	if got[0].Path() != "wow/eu/brumamar/nandu" || got[1].Path() != "wow/eu/zul/bob" || got[1].Steps != 3 || got[1].Updated != s.Now().Unix() {
		t.Errorf("claims = %+v", got)
	}
	if none, err := s.ClaimsOfKey(ctx, 999); err != nil || len(none) != 0 {
		t.Errorf("claims of a missing key = %v, %v", none, err)
	}
	if _, err := s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "eu", Realm: "zul", Name: "bob", GUID: "Player-1-00000009", KeyID: b.ID}); err == nil {
		t.Error("a second claim of the same path was accepted")
	}
}

func TestClaimUpdateQuotaAndDelete(t *testing.T) {
	s, clock := openTest(t)
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1), AllowOpen: true})
	s.Register(ctx, RegisterInput{Public: pubKey(2), Nonce: nonce(2), AllowOpen: true})
	a, b := mustKey(t, s, pubKey(1)), mustKey(t, s, pubKey(2))
	claim := func(name string, key int64) Claim {
		return Claim{Flavor: "wow", Region: "eu", Realm: "zul", Name: name, GUID: "Player-1-00000001", KeyID: key}
	}

	first, err := s.CreateClaimWithin(ctx, claim("one", a.ID), 2)
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.CreateClaimWithin(ctx, claim("two", a.ID), 2)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateClaimWithin(ctx, claim("three", a.ID), 2); !errors.Is(err, ErrClaimQuota) {
		t.Errorf("the third claim of a key with a limit of 2 gave %v", err)
	}
	if _, err := s.ClaimByPath(ctx, "wow", "eu", "zul", "three"); !errors.Is(err, ErrNotFound) {
		t.Errorf("the refused claim exists: %v", err)
	}
	if _, err := s.CreateClaimWithin(ctx, claim("three", b.ID), 2); err != nil {
		t.Errorf("another key hit the limit of this key: %v", err)
	}
	if _, err := s.CreateClaimWithin(ctx, claim("one", b.ID), 2); err == nil {
		t.Error("a claim of a taken path was accepted")
	}

	clock.Advance(time.Hour)
	if err := s.SetClaimData(ctx, first, 7, 100); err != nil {
		t.Fatal(err)
	}
	if err := s.SetClaimData(ctx, second, 1, 50); err != nil {
		t.Fatal(err)
	}
	got, err := s.ClaimByPath(ctx, "wow", "eu", "zul", "one")
	if err != nil || got.ID != first || got.Steps != 7 || got.DataBytes != 100 || got.Updated != clock.Now().Unix() || got.Created >= got.Updated {
		t.Errorf("claim = %+v, %v", got, err)
	}
	if n, err := s.DataBytesOfKey(ctx, a.ID, 0); err != nil || n != 150 {
		t.Errorf("DataBytesOfKey = %d, %v; want 150", n, err)
	}
	if n, err := s.DataBytesOfKey(ctx, a.ID, first); err != nil || n != 50 {
		t.Errorf("DataBytesOfKey except the first = %d, %v; want 50", n, err)
	}
	if err := s.SetClaimData(ctx, 999, 1, 1); !errors.Is(err, ErrNotFound) {
		t.Errorf("SetClaimData of a missing claim = %v", err)
	}

	if err := s.DeleteClaim(ctx, first); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteClaim(ctx, first); !errors.Is(err, ErrNotFound) {
		t.Errorf("second DeleteClaim = %v", err)
	}
	if _, err := s.CreateClaimWithin(ctx, claim("four", a.ID), 2); err != nil {
		t.Errorf("a delete did not free a place under the limit: %v", err)
	}

	if err := s.RevokeKey(ctx, b.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateClaimWithin(ctx, claim("five", b.ID), 2); !errors.Is(err, ErrKeyRevoked) {
		t.Errorf("a claim of a revoked key gave %v", err)
	}
	if _, err := s.ClaimByPath(ctx, "wow", "eu", "zul", "five"); !errors.Is(err, ErrNotFound) {
		t.Errorf("the refused claim of a revoked key exists: %v", err)
	}
}

func TestInviteCodesAreRandom(t *testing.T) {
	seen := map[string]bool{}
	for range 50 {
		code, err := newInviteCode()
		if err != nil || len(code) != 16 || seen[code] {
			t.Fatalf("code %q, %v (seen before: %v)", code, err, seen[code])
		}
		seen[code] = true
	}
}

func TestMigrationV2AddsShotsToAVersion1File(t *testing.T) {
	path := filepath.Join(t.TempDir(), "memories.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`DROP TABLE shots; DROP TABLE settings; ALTER TABLE keys DROP COLUMN open; ALTER TABLE keys DROP COLUMN max_data_bytes; ALTER TABLE keys DROP COLUMN max_shot_bytes; PRAGMA user_version = 1`); err != nil {
		t.Fatal(err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatalf("migration from version 1: %v", err)
	}
	defer s.Close()
	if _, err := s.db.Exec(`SELECT claim_id, file, upload_sha256, bytes FROM shots`); err != nil {
		t.Errorf("shots after the migration: %v", err)
	}
}

func TestShots(t *testing.T) {
	s, _ := openTest(t)
	s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1), AllowOpen: true})
	a := mustKey(t, s, pubKey(1))
	one, _ := s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "eu", Realm: "zul", Name: "one", GUID: "g1", KeyID: a.ID})
	two, _ := s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "eu", Realm: "zul", Name: "two", GUID: "g2", KeyID: a.ID})

	if _, err := s.ShotOf(ctx, one, "a.jpg"); !errors.Is(err, ErrNotFound) {
		t.Errorf("ShotOf before any write = %v", err)
	}
	for _, w := range []struct {
		claim int64
		file  string
		sha   byte
		n     int64
	}{{one, "a.jpg", 1, 100}, {one, "b.jpg", 2, 50}, {two, "a.jpg", 3, 7}} {
		if err := s.SetShot(ctx, w.claim, w.file, []byte{w.sha}, w.n); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.SetShot(ctx, one, "a.jpg", []byte{9}, 60); err != nil {
		t.Fatal(err)
	}
	sh, err := s.ShotOf(ctx, one, "a.jpg")
	if err != nil || !bytes.Equal(sh.UploadSHA256, []byte{9}) || sh.Bytes != 60 {
		t.Errorf("ShotOf = %+v, %v", sh, err)
	}
	c1, _ := s.ClaimByPath(ctx, "wow", "eu", "zul", "one")
	c2, _ := s.ClaimByPath(ctx, "wow", "eu", "zul", "two")
	if c1.ShotBytes != 110 || c2.ShotBytes != 7 {
		t.Errorf("shot_bytes = %d and %d; want 110 and 7", c1.ShotBytes, c2.ShotBytes)
	}
	if n, err := s.ShotBytesOfKey(ctx, a.ID); err != nil || n != 117 {
		t.Errorf("ShotBytesOfKey = %d, %v; want 117", n, err)
	}
	if err := s.SetShot(ctx, 999, "a.jpg", []byte{1}, 1); !errors.Is(err, ErrNotFound) {
		t.Errorf("SetShot of a missing claim = %v", err)
	}

	if err := s.DeleteClaim(ctx, one); err != nil {
		t.Fatalf("a claim with screenshots must delete: %v", err)
	}
	if _, err := s.ShotOf(ctx, one, "a.jpg"); !errors.Is(err, ErrNotFound) {
		t.Errorf("the shots of a deleted claim stay: %v", err)
	}
	if n, _ := s.ShotBytesOfKey(ctx, a.ID); n != 7 {
		t.Errorf("ShotBytesOfKey after the delete = %d; want 7", n)
	}
}

func TestSetKeyLimits(t *testing.T) {
	s, _ := openTest(t)
	registerInvited(t, s, pubKey(1))
	k := mustKey(t, s, pubKey(1))
	if k.MaxDataBytes != 0 || k.MaxShotBytes != 0 {
		t.Fatalf("a new key has limits %d and %d, want 0 and 0", k.MaxDataBytes, k.MaxShotBytes)
	}
	if err := s.SetKeyLimits(ctx, k.ID, 100, 200); err != nil {
		t.Fatal(err)
	}
	if k := mustKey(t, s, pubKey(1)); k.MaxDataBytes != 100 || k.MaxShotBytes != 200 {
		t.Errorf("limits = %d and %d, want 100 and 200", k.MaxDataBytes, k.MaxShotBytes)
	}
	if err := s.SetKeyLimits(ctx, 12345, 1, 1); !errors.Is(err, ErrNotFound) {
		t.Errorf("SetKeyLimits of a missing id = %v", err)
	}
}
