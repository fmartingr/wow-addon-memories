package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/characters"
	"github.com/fmartingr/wow-addon-memories/server/internal/ids"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

// busyRetry is the Retry-After of a 503 for a full upload queue.
const busyRetry = 5 * time.Second

// acquire waits for an upload slot. It returns false after it answered, or when the client left.
func (a *API) acquire(w http.ResponseWriter, r *http.Request) bool {
	select {
	case a.slots <- struct{}{}:
		return true
	default:
	}
	timer := time.NewTimer(a.uploadWait)
	defer timer.Stop()
	select {
	case a.slots <- struct{}{}:
		return true
	case <-r.Context().Done():
		return false
	case <-timer.C:
		w.Header().Set("Retry-After", apierr.RetryAfter(busyRetry))
		apierr.Write(w, http.StatusServiceUnavailable, "busy",
			"The server is busy with other uploads. Wait "+apierr.RetryAfter(busyRetry)+" seconds, then try again.")
		return false
	}
}

func (a *API) release() { <-a.slots }

func (a *API) limits() validate.Limits {
	return validate.Limits{
		MaxDecodedBytes: a.cfg.MaxDecodedBytes,
		MaxText:         a.cfg.MaxText,
		MaxRecords:      a.cfg.MaxRecords,
		MaxChunks:       a.cfg.MaxChunks,
		MaxPoints:       a.cfg.MaxPoints,
	}
}

// maxCharacterBytes is twice the largest decoded upload, so a character keeps room for the records that its client
// no longer sends, and a save holds at most about three uploads of data: the stored one, the new one and the merge.
func maxCharacterBytes(maxDecoded int64) int64 { return 2 * maxDecoded }

func (a *API) handleUpload(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	if !strings.EqualFold(strings.TrimSpace(r.Header.Get("Content-Encoding")), "gzip") {
		apierr.Write(w, http.StatusUnsupportedMediaType, "gzip_required",
			"The upload must be gzip data with the header Content-Encoding: gzip. Update the app.")
		return
	}
	if !a.acquire(w, r) {
		return
	}
	defer a.release()

	up, problems := validate.Read(r.Body, a.limits(), a.store.Now())
	if len(problems) > 0 {
		if validate.TooLarge(problems) {
			apierr.Write(w, http.StatusRequestEntityTooLarge, "too_large", problems[0].Reason+" Upload fewer records, or ask the website admin to raise the limit.")
			return
		}
		apierr.JSON(w, http.StatusUnprocessableEntity, map[string]any{
			"error":    "invalid",
			"message":  "The upload has data that this website does not accept. Nothing was stored. The problems list what to fix.",
			"problems": problems,
		})
		return
	}

	res, err := a.chars.Save(r.Context(), *id.Key, up, characters.Quotas{
		MaxCharacters:     a.cfg.MaxCharactersPerKey,
		MaxDataBytes:      id.Key.DataLimit(a.gate.Current().Settings.MaxDataBytes, a.cfg.MaxDataBytesPerKey),
		MaxCharacterBytes: maxCharacterBytes(a.cfg.MaxDecodedBytes),
	})
	switch {
	case errors.Is(err, store.ErrKeyRevoked):
		apierr.KeyRevoked(w)
	case errors.Is(err, characters.ErrClaimed):
		apierr.Write(w, http.StatusConflict, "claimed",
			"Another key already owns this character's web address. If that was you with an older key, ask the website admin to move it to this key.")
	case errors.Is(err, characters.ErrGUIDMismatch):
		apierr.Write(w, http.StatusConflict, "guid_mismatch",
			"This web address belongs to another character of the same name. Nothing was stored. Ask the website admin if the address should change.")
	case errors.Is(err, characters.ErrCharacterQuota):
		apierr.Write(w, http.StatusInsufficientStorage, "quota",
			"This key already has the most characters that the website allows. Remove a character from the website, then try again.")
	case errors.Is(err, characters.ErrCharacterTooLarge):
		apierr.Write(w, http.StatusRequestEntityTooLarge, "too_large",
			"This character's stored data would grow past the most that the website keeps for one character. Remove the character from the website, then upload it again.")
	case errors.Is(err, characters.ErrDataQuota):
		apierr.Write(w, http.StatusInsufficientStorage, "quota",
			"This key already holds the most data that the website allows. Remove a character from the website, then try again.")
	case err != nil:
		a.internal(w, "upload", err)
	default:
		apierr.JSON(w, http.StatusOK, map[string]any{
			"path":  res.Path,
			"url":   a.characterURL(res.Path),
			"steps": res.Steps,
			"added": res.Added,
		})
	}
}

// charPath reads the character path of the URL. It returns false when a segment is not a valid one.
func charPath(r *http.Request) (characters.Path, bool) {
	p := characters.Path{
		Flavor: r.PathValue("flavor"), Region: r.PathValue("region"), Realm: r.PathValue("realm"), Name: r.PathValue("name"),
	}
	for _, seg := range []string{p.Flavor, p.Region, p.Realm, p.Name} {
		if !ids.Pattern.MatchString(seg) {
			return characters.Path{}, false
		}
	}
	return p, true
}

func (a *API) handleDelete(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	p, ok := charPath(r)
	if !ok {
		notFound(w)
		return
	}
	err := a.chars.Delete(r.Context(), p, id.Key.ID)
	switch {
	case errors.Is(err, store.ErrNotFound):
		notFound(w)
	case err != nil:
		a.internal(w, "delete", err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

func notFound(w http.ResponseWriter) {
	apierr.Write(w, http.StatusNotFound, "not_found", "This website has no such character for this key.")
}
