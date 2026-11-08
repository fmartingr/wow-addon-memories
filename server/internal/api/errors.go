package api

import (
	"net/http"

	"github.com/fmartingr/wow-addon-memories/server/internal/apierr"
)

// internal logs the failure without any request data and answers 500.
func (a *API) internal(w http.ResponseWriter, what string, err error) {
	apierr.Fail(w, a.log, "request failed", what, err)
}

func badRequest(w http.ResponseWriter, message string) {
	apierr.Write(w, http.StatusBadRequest, "bad_request", message)
}
