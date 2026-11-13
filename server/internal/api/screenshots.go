package api

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net/http"
	"path"

	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
	"github.com/fmartingr/wow-addon-memories/server/internal/characters"
	"github.com/fmartingr/wow-addon-memories/server/internal/images"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
	"github.com/fmartingr/wow-addon-memories/server/internal/validate"
)

func (a *API) handleScreenshot(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	p, ok := charPath(r)
	if !ok {
		notFound(w)
		return
	}
	// A stranger learns nothing about the path, so the owner check comes before the approval check. SaveScreenshot
	// checks the owner again under the lock of the path, because a delete can run in between.
	claim, err := a.store.ClaimByPath(r.Context(), p.Flavor, p.Region, p.Realm, p.Name)
	switch {
	case errors.Is(err, store.ErrNotFound) || (err == nil && claim.KeyID != id.Key.ID):
		notFound(w)
		return
	case err != nil:
		a.internal(w, "screenshot claim", err)
		return
	}
	if id.Key.Open {
		screenshotsUnavailable(w)
		return
	}
	if id.Key.Screenshots != store.ShotsApproved {
		apierr.Write(w, http.StatusForbidden, "screenshots_not_approved",
			"This key has no approval to upload screenshots. Use Request screenshots in the app, then wait for the website admin to approve it.")
		return
	}
	file := r.PathValue("file")
	if !validate.ScreenshotPattern.MatchString("screenshots/" + file) {
		notReferenced(w)
		return
	}
	// A record can name a .tga file, so the name passes the pattern; it is refused before the slot and the read of
	// the stored journey.
	if !images.Supported(path.Ext(file)) {
		unsupportedImage(w)
		return
	}
	if !a.acquire(w, r) {
		return
	}
	defer a.release()
	// The body is in memory already: the signature covers it, so the middleware read it up to MaxShotBytes. The copy
	// comes after the slot, so a request that waits holds only the copy of the middleware. io.Copy hands the whole
	// body to the buffer in one write, so the copy takes one allocation of its size.
	var body bytes.Buffer
	if _, err := io.Copy(&body, r.Body); err != nil {
		badRequest(w, "The server could not read the screenshot. Try again.")
		return
	}

	created, err := a.chars.SaveScreenshot(r.Context(), *id.Key, p, file, body.Bytes(), characters.ShotLimits{
		MaxPixels:   a.cfg.MaxPixels,
		MaxKeyBytes: a.cfg.MaxShotBytesPerKey,
	})
	switch {
	case errors.Is(err, store.ErrNotFound):
		notFound(w)
	case errors.Is(err, characters.ErrNotReferenced):
		notReferenced(w)
	case errors.Is(err, images.ErrUnsupported):
		unsupportedImage(w)
	case errors.Is(err, images.ErrTooManyPixels):
		apierr.Write(w, http.StatusRequestEntityTooLarge, "too_large",
			fmt.Sprintf("The image has more than %d pixels, which is the most that the website takes. Ask the website admin to raise the limit.", a.cfg.MaxPixels))
	case errors.Is(err, characters.ErrShotQuota):
		apierr.Write(w, http.StatusInsufficientStorage, "quota",
			"This key already holds the most screenshot data that the website allows. Remove a character from the website, then try again.")
	case err != nil:
		a.internal(w, "screenshot", err)
	case created:
		apierr.JSON(w, http.StatusCreated, map[string]any{"file": file})
	default:
		apierr.JSON(w, http.StatusOK, map[string]any{"file": file})
	}
}

func unsupportedImage(w http.ResponseWriter) {
	apierr.Write(w, http.StatusUnsupportedMediaType, "unsupported_image",
		"The file is not an 8-bit colour or grey JPEG or PNG image whose content matches its file name, or it is damaged. The website does not take TGA, CMYK or 16-bit files.")
}

func screenshotsUnavailable(w http.ResponseWriter) {
	apierr.Write(w, http.StatusForbidden, "screenshots_unavailable",
		"This key registered without an invite, and the website takes screenshots only from keys that registered with an invite code.")
}

func notReferenced(w http.ResponseWriter) {
	apierr.Write(w, http.StatusNotFound, "not_referenced",
		"No stored record of this character names this screenshot. Upload the character's journey with this key first, once the key is approved for screenshots.")
}
