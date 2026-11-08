package api

import (
	"net/http"

	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
	"github.com/fmartingr/wow-addon-memories/server/internal/auth"
)

type characterInfo struct {
	Path    string `json:"path"`
	URL     string `json:"url"`
	GUID    string `json:"guid"`
	Steps   int64  `json:"steps"`
	Updated int64  `json:"updated"`
}

// characterURL is the page of the character at path.
func (a *API) characterURL(path string) string { return a.cfg.SiteURL + "/" + path + "/" }

func (a *API) handleMe(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	claims, err := a.store.ClaimsOfKey(r.Context(), id.Key.ID)
	if err != nil {
		a.internal(w, "me", err)
		return
	}
	chars := make([]characterInfo, 0, len(claims))
	for _, c := range claims {
		chars = append(chars, characterInfo{
			Path:    c.Path(),
			URL:     a.characterURL(c.Path()),
			GUID:    c.GUID,
			Steps:   c.Steps,
			Updated: c.Updated,
		})
	}
	apierr.JSON(w, http.StatusOK, map[string]any{"screenshots": id.Key.Screenshots, "characters": chars})
}

func (a *API) handleScreenshotsRequest(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	state, err := a.store.RequestScreenshots(r.Context(), id.Key.ID)
	if err != nil {
		a.internal(w, "screenshots request", err)
		return
	}
	apierr.JSON(w, http.StatusOK, map[string]string{"screenshots": state})
}
