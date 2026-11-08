package characters

import (
	"bytes"
	"errors"
	"io"
	"log/slog"
	"strconv"
	"strings"
	"testing"

	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

func TestMoveHoldsTheClaimForTheNewKey(t *testing.T) {
	f := newFixture(t)
	a, b := f.key(1), f.key(2)
	p := Path{"wow", "eu", "brumamar", "nandu"}
	if _, err := f.svc.Save(ctx, a, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Move(ctx, p, b.ID); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Move(ctx, p, b.ID); !errors.Is(err, ErrAlreadyOwner) {
		t.Errorf("move to the owner = %v, want ErrAlreadyOwner", err)
	}
	if _, err := f.svc.Save(ctx, a, upload(t, "eu-brumamar-nandu"), roomy); !errors.Is(err, ErrClaimed) {
		t.Errorf("the old key saved after the move: %v", err)
	}
	if _, err := f.svc.Save(ctx, b, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
		t.Errorf("the new key can not save: %v", err)
	}
	if err := f.svc.Move(ctx, Path{"wow", "eu", "nowhere", "x"}, b.ID); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("move of a missing path = %v", err)
	}
	if err := f.st.RevokeKey(ctx, a.ID); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Move(ctx, p, a.ID); !errors.Is(err, store.ErrKeyRevoked) {
		t.Errorf("move to a revoked key = %v", err)
	}
}

func TestStripScreenshotsRemovesFieldsFilesAndRows(t *testing.T) {
	f := newFixture(t)
	k, other := f.key(1), f.key(2)
	if err := f.st.SetScreenshots(ctx, k.ID, store.ShotsApproved); err != nil {
		t.Fatal(err)
	}
	k.Screenshots = store.ShotsApproved
	if _, err := f.svc.Save(ctx, k, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Save(ctx, other, upload(t, "eu-los-errantes-nandu"), roomy); err != nil {
		t.Fatal(err)
	}
	claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	id := strconv.FormatInt(claim.ID, 10)
	const shot = "WoWScrnShot_110126_114820.jpg"
	if err := f.blobs.Write(ctx, id+"/screenshots/"+shot, bytes.NewReader([]byte("jpeg"))); err != nil {
		t.Fatal(err)
	}
	if err := f.st.SetShot(ctx, claim.ID, shot, []byte("h"), 4); err != nil {
		t.Fatal(err)
	}
	otherClaim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "los-errantes", "nandu")
	journeyBefore := f.storedFile(otherClaim, "journey.jsonl")

	n, err := f.svc.StripScreenshots(ctx, k.ID)
	if err != nil || n != 1 {
		t.Fatalf("StripScreenshots = %d, %v; want 1", n, err)
	}
	if f.exists(id + "/screenshots/" + shot) {
		t.Error("the screenshot file stayed")
	}
	if strings.Contains(string(f.storedFile(claim, "journey.jsonl")), `"screenshot"`) {
		t.Error("a record still has a screenshot field")
	}
	if !strings.Contains(string(f.storedFile(claim, "entry.json")), `"screenshots": 0`) {
		t.Errorf("entry.json = %s", f.storedFile(claim, "entry.json"))
	}
	if !bytes.Equal(f.storedFile(otherClaim, "journey.jsonl"), journeyBefore) {
		t.Error("another key's journey changed")
	}
	after, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	if after.ShotBytes != 0 {
		t.Errorf("shot_bytes = %d", after.ShotBytes)
	}

	// A second run finds nothing to change and still succeeds.
	if n, err := f.svc.StripScreenshots(ctx, k.ID); err != nil || n != 1 {
		t.Errorf("second run = %d, %v", n, err)
	}
	// A claim that moved to another key between the list and the lock is left alone.
	if stripped, err := f.svc.stripClaim(ctx, Path{"wow", "eu", "los-errantes", "nandu"}, k.ID); err != nil || stripped {
		t.Errorf("stripClaim of a foreign claim = %v, %v; want false and no error", stripped, err)
	}
	if stripped, err := f.svc.stripClaim(ctx, Path{"wow", "eu", "nowhere", "x"}, k.ID); err != nil || stripped {
		t.Errorf("stripClaim of a missing claim = %v, %v; want false and no error", stripped, err)
	}
}

func TestStripScreenshotsOfAClaimWithNoFiles(t *testing.T) {
	f := newFixture(t)
	k := f.key(1)
	id, err := f.st.CreateClaim(ctx, store.Claim{Flavor: "wow", Region: "eu", Realm: "r", Name: "n", GUID: "Player-1-0000ABCD", KeyID: k.ID, ShotBytes: 3})
	if err != nil {
		t.Fatal(err)
	}
	if n, err := f.svc.StripScreenshots(ctx, k.ID); err != nil || n != 1 {
		t.Fatalf("StripScreenshots = %d, %v", n, err)
	}
	if c, _ := f.st.ClaimByPath(ctx, "wow", "eu", "r", "n"); c.ID != id || c.ShotBytes != 0 {
		t.Errorf("claim = %+v", c)
	}
}

func TestStripScreenshotsReportsADamagedCharacter(t *testing.T) {
	f := newFixture(t)
	k := f.key(1)
	if err := f.st.SetScreenshots(ctx, k.ID, store.ShotsApproved); err != nil {
		t.Fatal(err)
	}
	k.Screenshots = store.ShotsApproved
	for _, name := range []string{"eu-brumamar-nandu", "eu-los-errantes-nandu"} {
		if _, err := f.svc.Save(ctx, k, upload(t, name), roomy); err != nil {
			t.Fatal(err)
		}
	}
	claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	id := strconv.FormatInt(claim.ID, 10)
	if err := f.blobs.Write(ctx, id+"/character.json", strings.NewReader("{")); err != nil {
		t.Fatal(err)
	}
	const shot = "WoWScrnShot_110126_114820.jpg"
	if err := f.blobs.Write(ctx, id+"/screenshots/"+shot, bytes.NewReader([]byte("jpeg"))); err != nil {
		t.Fatal(err)
	}
	if err := f.st.SetShot(ctx, claim.ID, shot, []byte("h"), 4); err != nil {
		t.Fatal(err)
	}
	n, err := f.svc.StripScreenshots(ctx, k.ID)
	if err == nil {
		t.Error("a damaged character gave no error")
	}
	if n != 1 {
		t.Errorf("StripScreenshots cleaned %d characters, want the 1 after the damaged one", n)
	}
	if f.exists(id + "/screenshots/" + shot) {
		t.Error("the screenshot file of the damaged character stayed")
	}
	if c, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); c.ShotBytes != 0 {
		t.Errorf("shot_bytes of the damaged character = %d", c.ShotBytes)
	}
	other, _ := f.st.ClaimByPath(ctx, "wow", "eu", "los-errantes", "nandu")
	if strings.Contains(string(f.storedFile(other, "journey.jsonl")), `"screenshot"`) {
		t.Error("the character after the damaged one kept its screenshot fields")
	}
	f.st.Close()
	if _, err := f.svc.StripScreenshots(ctx, k.ID); err == nil {
		t.Error("a closed store gave no error")
	}
}

func TestSaveReadsTheScreenshotStateUnderTheLock(t *testing.T) {
	f := newFixture(t)
	k := f.key(1)
	// The key was approved when the request was authenticated; the admin revoked screenshots since.
	stale := k
	stale.Screenshots = store.ShotsApproved
	if err := f.st.SetScreenshots(ctx, k.ID, store.ShotsDenied); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Save(ctx, stale, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
		t.Fatal(err)
	}
	claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
	if strings.Contains(string(f.storedFile(claim, "journey.jsonl")), `"screenshot"`) {
		t.Error("a save with a stale approval kept the screenshot fields")
	}
}

func TestStripScreenshotsRepairsAnInterruptedRun(t *testing.T) {
	for _, failing := range []string{"entry.json", "journey.jsonl"} {
		t.Run(failing, func(t *testing.T) {
			f := newFixture(t)
			k := f.key(1)
			if err := f.st.SetScreenshots(ctx, k.ID, store.ShotsApproved); err != nil {
				t.Fatal(err)
			}
			k.Screenshots = store.ShotsApproved
			if _, err := f.svc.Save(ctx, k, upload(t, "eu-brumamar-nandu"), roomy); err != nil {
				t.Fatal(err)
			}
			flaky := &flakyBlobs{Blobs: f.blobs, failWrite: func(name string) bool { return name == failing }}
			svc := New(f.st, flaky, slog.New(slog.NewJSONHandler(io.Discard, nil)))
			if _, err := svc.StripScreenshots(ctx, k.ID); err == nil {
				t.Fatal("the failed write gave no error")
			}
			flaky.failWrite = nil
			if n, err := svc.StripScreenshots(ctx, k.ID); err != nil || n != 1 {
				t.Fatalf("second run = %d, %v", n, err)
			}
			claim, _ := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu")
			if strings.Contains(string(f.storedFile(claim, "journey.jsonl")), `"screenshot"`) {
				t.Error("a record still has a screenshot field")
			}
			if !strings.Contains(string(f.storedFile(claim, "entry.json")), `"screenshots": 0`) {
				t.Errorf("entry.json = %s", f.storedFile(claim, "entry.json"))
			}
			var total int64
			for _, n := range dataFiles {
				total += int64(len(f.storedFile(claim, n)))
			}
			if claim.DataBytes != total {
				t.Errorf("data_bytes = %d, want %d", claim.DataBytes, total)
			}
		})
	}
}

func TestSaveOfANewPathByAKeyRevokedSinceAuthIsRefused(t *testing.T) {
	f := newFixture(t)
	k := f.key(1)
	// k was read at authentication; the admin revoked the key since.
	if err := f.st.RevokeKey(ctx, k.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Save(ctx, k, upload(t, "eu-brumamar-nandu"), roomy); !errors.Is(err, store.ErrKeyRevoked) {
		t.Errorf("Save = %v, want store.ErrKeyRevoked", err)
	}
	if _, err := f.st.ClaimByPath(ctx, "wow", "eu", "brumamar", "nandu"); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("a revoked key claimed a path: %v", err)
	}
}
