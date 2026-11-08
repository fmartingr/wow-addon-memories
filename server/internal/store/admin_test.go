package store

import (
	"errors"
	"testing"
	"time"
)

func TestFingerprintIsTheFirst16HexOfTheSHA256(t *testing.T) {
	// sha256 of 32 bytes of 0x01.
	if got := Fingerprint(pubKey(1)); got != "72cd6e8422c407fb" {
		t.Errorf("Fingerprint = %q", got)
	}
	if got := mustKey(t, openWithKey(t), pubKey(1)).Fingerprint(); got != "72cd6e8422c407fb" {
		t.Errorf("Key.Fingerprint = %q", got)
	}
}

func openWithKey(t *testing.T) *Store {
	t.Helper()
	s, _ := openTest(t)
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1)}); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestListKeysAndLookups(t *testing.T) {
	s, _ := openTest(t)
	_, code, err := s.CreateInvite(ctx, "for Ana", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := register(t, s, pubKey(1), code); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(2), Nonce: nonce(2)}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(3), Nonce: nonce(3)}); err != nil {
		t.Fatal(err)
	}
	k1, k2, k3 := mustKey(t, s, pubKey(1)), mustKey(t, s, pubKey(2)), mustKey(t, s, pubKey(3))
	if _, err := s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "eu", Realm: "r", Name: "n", GUID: "g", KeyID: k1.ID, DataBytes: 10, ShotBytes: 5}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "eu", Realm: "r", Name: "m", GUID: "h", KeyID: k1.ID, DataBytes: 20, ShotBytes: 7}); err != nil {
		t.Fatal(err)
	}
	for _, id := range []int64{k1.ID, k3.ID} {
		if _, err := s.RequestScreenshots(ctx, id); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.RevokeKey(ctx, k3.ID); err != nil {
		t.Fatal(err)
	}

	all, err := s.ListKeys(ctx, false, 10)
	if err != nil || len(all) != 3 || all[0].ID != k3.ID || all[2].ID != k1.ID {
		t.Fatalf("ListKeys = %+v, %v; want 3 keys, newest first", all, err)
	}
	if r := all[2]; r.InviteNote != "for Ana" || r.Characters != 2 || r.DataBytes != 30 || r.ShotBytes != 12 || r.Screenshots != ShotsPending {
		t.Errorf("key row = %+v", r)
	}
	if r := all[1]; r.InviteNote != "" || r.Characters != 0 || r.Revoked {
		t.Errorf("key row = %+v", r)
	}
	if !all[0].Revoked {
		t.Error("the revoked flag is lost")
	}
	if one, _ := s.ListKeys(ctx, false, 1); len(one) != 1 {
		t.Errorf("limit 1 gave %d rows", len(one))
	}
	pending, err := s.ListKeys(ctx, true, 10)
	if err != nil || len(pending) != 1 || pending[0].ID != k1.ID {
		t.Errorf("pending = %+v, %v; want only key 1 (key 3 is revoked)", pending, err)
	}

	if got, err := s.KeyByID(ctx, k2.ID); err != nil || got.Fingerprint() != Fingerprint(pubKey(2)) {
		t.Errorf("KeyByID = %+v, %v", got, err)
	}
	if _, err := s.KeyByID(ctx, 999); !errors.Is(err, ErrNotFound) {
		t.Errorf("KeyByID of a missing key = %v", err)
	}
	if got, err := s.KeyByFingerprint(ctx, "  "+Fingerprint(pubKey(2))+" "); err != nil || got.ID != k2.ID {
		t.Errorf("KeyByFingerprint = %+v, %v", got, err)
	}
	for _, fp := range []string{"", "0000000000000000", "72cd"} {
		if _, err := s.KeyByFingerprint(ctx, fp); !errors.Is(err, ErrNotFound) {
			t.Errorf("KeyByFingerprint(%q) = %v, want not found", fp, err)
		}
	}
}

func TestDecideScreenshotsOnlyMovesAPendingKey(t *testing.T) {
	s, _ := openTest(t)
	if _, err := s.Register(ctx, RegisterInput{Public: pubKey(1), Nonce: nonce(1)}); err != nil {
		t.Fatal(err)
	}
	k := mustKey(t, s, pubKey(1))
	if ok, err := s.DecideScreenshots(ctx, k.ID, ShotsApproved); ok || err != nil {
		t.Errorf("approve of a key with no request = %v, %v", ok, err)
	}
	s.RequestScreenshots(ctx, k.ID)
	if ok, err := s.DecideScreenshots(ctx, k.ID, ShotsApproved); !ok || err != nil {
		t.Fatalf("approve of a pending key = %v, %v", ok, err)
	}
	if ok, _ := s.DecideScreenshots(ctx, k.ID, ShotsDenied); ok {
		t.Error("a deny moved an approved key")
	}
	s.SetScreenshots(ctx, k.ID, ShotsPending)
	s.RevokeKey(ctx, k.ID)
	if ok, _ := s.DecideScreenshots(ctx, k.ID, ShotsApproved); ok {
		t.Error("a revoked key was approved")
	}
}

func TestListInvitesStates(t *testing.T) {
	s, clock := openTest(t)
	_, spent, _ := s.CreateInvite(ctx, "spent", time.Hour)
	id2, _, _ := s.CreateInvite(ctx, "revoked", time.Hour)
	s.CreateInvite(ctx, "open", time.Hour)
	if _, err := register(t, s, pubKey(1), spent); err != nil {
		t.Fatal(err)
	}
	if err := s.RevokeInvite(ctx, id2); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Minute)
	rows, err := s.ListInvites(ctx, 10)
	if err != nil || len(rows) != 3 || rows[0].Note != "open" {
		t.Fatalf("ListInvites = %+v, %v", rows, err)
	}
	if r := rows[2]; r.UsedBy != Fingerprint(pubKey(1)) || r.UsedAt == 0 || r.Revoked {
		t.Errorf("spent invite = %+v", r)
	}
	if r := rows[1]; !r.Revoked || r.UsedBy != "" {
		t.Errorf("revoked invite = %+v", r)
	}
	if r := rows[0]; r.Expires-r.Created != 3600 || r.UsedBy != "" {
		t.Errorf("open invite = %+v", r)
	}
	if got, _ := s.ListInvites(ctx, 2); len(got) != 2 {
		t.Errorf("limit 2 gave %d rows", len(got))
	}
}

func TestSearchClaimsMoveAndClearShots(t *testing.T) {
	s, _ := openTest(t)
	for n := byte(1); n <= 2; n++ {
		if _, err := s.Register(ctx, RegisterInput{Public: pubKey(n), Nonce: nonce(n)}); err != nil {
			t.Fatal(err)
		}
	}
	k1, k2 := mustKey(t, s, pubKey(1)), mustKey(t, s, pubKey(2))
	a, _ := s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "eu", Realm: "brumamar", Name: "nandu", GUID: "Player-1-0000ABCD", KeyID: k1.ID, ShotBytes: 9})
	s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "us", Realm: "a_b", Name: "x", GUID: "Player-1-0000DCBA", KeyID: k2.ID})
	s.CreateClaim(ctx, Claim{Flavor: "wow", Region: "us", Realm: "azzb", Name: "y", GUID: "Player-1-0000EEEE", KeyID: k2.ID})
	if err := s.SetShot(ctx, a, "WoWScrnShot_110126_114820.jpg", []byte("h"), 9); err != nil {
		t.Fatal(err)
	}
	if err := s.RevokeKey(ctx, k2.ID); err != nil {
		t.Fatal(err)
	}

	count := func(q string, key int64) int {
		rows, err := s.SearchClaims(ctx, q, key, 10)
		if err != nil {
			t.Fatal(err)
		}
		return len(rows)
	}
	for _, tc := range []struct {
		q    string
		key  int64
		want int
	}{
		{"", 0, 3}, {"brumamar", 0, 1}, {"WOW/EU", 0, 1}, {"player-1-0000abcd", 0, 1}, {"0000", 0, 3},
		{"a_b", 0, 1}, {"_", 0, 1}, {"%", 0, 0}, {`\`, 0, 0}, {"nothing", 0, 0}, {"", k2.ID, 2}, {"x", k2.ID, 1}, {"nandu", k2.ID, 0},
	} {
		if got := count(tc.q, tc.key); got != tc.want {
			t.Errorf("SearchClaims(%q, key %d) = %d rows, want %d", tc.q, tc.key, got, tc.want)
		}
	}
	if rows, _ := s.SearchClaims(ctx, "", 0, 1); len(rows) != 1 {
		t.Errorf("limit 1 gave %d rows", len(rows))
	}
	rows, _ := s.SearchClaims(ctx, "x", 0, 10)
	if len(rows) != 1 || !rows[0].OwnerRevoked || Fingerprint(rows[0].OwnerKey) != Fingerprint(pubKey(2)) || rows[0].Path() != "wow/us/a_b/x" {
		t.Errorf("row = %+v", rows)
	}

	if err := s.MoveClaim(ctx, a, k2.ID); !errors.Is(err, ErrKeyRevoked) {
		t.Errorf("move to a revoked key = %v", err)
	}
	if err := s.MoveClaim(ctx, a, 999); !errors.Is(err, ErrNotFound) {
		t.Errorf("move to a missing key = %v", err)
	}
	if err := s.MoveClaim(ctx, 999, k1.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("move of a missing claim = %v", err)
	}
	k3 := func() Key {
		if _, err := s.Register(ctx, RegisterInput{Public: pubKey(3), Nonce: nonce(3)}); err != nil {
			t.Fatal(err)
		}
		return mustKey(t, s, pubKey(3))
	}()
	if err := s.MoveClaim(ctx, a, k3.ID); err != nil {
		t.Fatal(err)
	}
	if c, _ := s.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); c.KeyID != k3.ID {
		t.Errorf("owner = %d, want %d", c.KeyID, k3.ID)
	}

	if err := s.ClearShots(ctx, a); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ShotOf(ctx, a, "WoWScrnShot_110126_114820.jpg"); !errors.Is(err, ErrNotFound) {
		t.Errorf("the shot row stayed: %v", err)
	}
	if c, _ := s.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); c.ShotBytes != 0 {
		t.Errorf("shot_bytes = %d", c.ShotBytes)
	}
}
