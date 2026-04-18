package handler

import (
	"encoding/json"
	"net/http"
)

// VersionHandler returns build metadata (version + commit) as JSON.
type VersionHandler struct {
	version string
	commit  string
}

// NewVersionHandler creates a new version handler with the given build metadata.
func NewVersionHandler(version, commit string) *VersionHandler {
	return &VersionHandler{version: version, commit: commit}
}

func (h *VersionHandler) Serve(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"version": h.version,
		"commit":  h.commit,
	})
}