package store

import (
	"errors"
	"math"
	"strings"
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

	list, err := s.ListKeys(ctx, "", 1, 10)
	all := list.Rows
	if err != nil || len(all) != 3 || list.Total != 3 || all[0].ID != k3.ID || all[2].ID != k1.ID {
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
	if one, _ := s.ListKeys(ctx, "", 1, 1); len(one.Rows) != 1 || one.Total != 3 || one.Pages != 3 {
		t.Errorf("size 1 gave %+v", one)
	}
	pending, err := s.ListRequests(ctx, "", 1, 10)
	if err != nil || len(pending.Rows) != 1 || pending.Rows[0].ID != k1.ID {
		t.Errorf("pending = %+v, %v; want only key 1 (key 3 is revoked)", pending, err)
	}
	for _, tc := range []struct {
		q    string
		want []int64
	}{
		{Fingerprint(pubKey(2)), []int64{k2.ID}},
		{strings.ToUpper(Fingerprint(pubKey(2))[:6]), []int64{k2.ID}},
		{"ana", []int64{k1.ID}},
		{"pend", []int64{k3.ID, k1.ID}},
		{"NONE", []int64{k2.ID}},
		{"%", nil},
		{"_", nil},
		{`\`, nil},
		{"nothing", nil},
	} {
		got, err := s.ListKeys(ctx, tc.q, 1, 10)
		if err != nil || len(got.Rows) != len(tc.want) || got.Total != len(tc.want) {
			t.Errorf("ListKeys(%q) = %d rows of %d, %v; want %d", tc.q, len(got.Rows), got.Total, err, len(tc.want))
			continue
		}
		for i, r := range got.Rows {
			if r.ID != tc.want[i] {
				t.Errorf("ListKeys(%q)[%d] = key %d, want %d", tc.q, i, r.ID, tc.want[i])
			}
		}
	}
	if got, _ := s.ListRequests(ctx, "ana", 1, 10); len(got.Rows) != 1 {
		t.Errorf("ListRequests by note = %d rows", len(got.Rows))
	}
	if got, _ := s.ListRequests(ctx, "pending", 1, 10); len(got.Rows) != 0 {
		t.Error("ListRequests searches the screenshot state")
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
	list, err := s.ListInvites(ctx, "", 1, 10)
	rows := list.Rows
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
	if got, _ := s.ListInvites(ctx, "", 1, 2); len(got.Rows) != 2 || got.Total != 3 {
		t.Errorf("size 2 gave %+v", got)
	}
	s.CreateInvite(ctx, "50%_off", time.Second)
	clock.Advance(time.Minute)
	for _, tc := range []struct {
		q    string
		want int
	}{
		{"SPEN", 1}, {"unused", 1}, {"used", 1}, {"USED", 1}, {"revoked", 1}, {"expired", 1}, {"open", 1},
		{"50%", 1}, {"%", 1}, {"_", 1}, {"0%_o", 1}, {"5_%", 0}, {"nothing", 0},
	} {
		if got, err := s.ListInvites(ctx, tc.q, 1, 10); err != nil || len(got.Rows) != tc.want {
			t.Errorf("ListInvites(%q) = %d rows, %v; want %d", tc.q, len(got.Rows), err, tc.want)
		}
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

	count := func(q string) int {
		l, err := s.SearchClaims(ctx, q, 1, 10)
		if err != nil {
			t.Fatal(err)
		}
		return len(l.Rows)
	}
	for _, tc := range []struct {
		q    string
		want int
	}{
		{"", 3}, {"brumamar", 1}, {"WOW/EU", 1}, {"player-1-0000abcd", 1}, {"0000", 3},
		{"a_b", 1}, {"_", 1}, {"%", 0}, {`\`, 0}, {"nothing", 0},
		{Fingerprint(pubKey(2)), 2}, {Fingerprint(pubKey(1)), 1}, {strings.ToUpper(Fingerprint(pubKey(1))), 1},
	} {
		if got := count(tc.q); got != tc.want {
			t.Errorf("SearchClaims(%q) = %d rows, want %d", tc.q, got, tc.want)
		}
	}
	if l, _ := s.SearchClaims(ctx, "", 1, 1); len(l.Rows) != 1 || l.Total != 3 || l.Pages != 3 {
		t.Errorf("size 1 gave %+v", l)
	}
	l, _ := s.SearchClaims(ctx, "x", 1, 10)
	rows := l.Rows
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

func TestListingsClampThePage(t *testing.T) {
	for _, tc := range []struct {
		total, page, size   int
		wantPage, wantPages int
		wantRows            int
	}{
		{0, 1, 25, 1, 1, 0},
		{0, 7, 25, 1, 1, 0},
		{25, 1, 25, 1, 1, 25},
		{25, 2, 25, 1, 1, 25},
		{26, 1, 25, 1, 2, 25},
		{26, 2, 25, 2, 2, 1},
		{26, 3, 25, 2, 2, 1},
		{26, 0, 25, 1, 2, 25},
		{26, -4, 25, 1, 2, 25},
		{26, math.MaxInt32, 25, 2, 2, 1},
	} {
		s, _ := openTest(t)
		for n := 0; n < tc.total; n++ {
			if _, _, err := s.CreateInvite(ctx, "n", time.Hour); err != nil {
				t.Fatal(err)
			}
		}
		got, err := s.ListInvites(ctx, "", tc.page, tc.size)
		if err != nil || got.Page != tc.wantPage || got.Pages != tc.wantPages || len(got.Rows) != tc.wantRows || got.Total != tc.total {
			t.Errorf("%+v: got page %d of %d with %d rows of %d, %v", tc, got.Page, got.Pages, len(got.Rows), got.Total, err)
		}
	}
}
