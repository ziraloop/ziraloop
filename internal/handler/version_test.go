package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestVersionHandler_Serve(t *testing.T) {
	h := NewVersionHandler("1.2.3", "abc1234")

	req := httptest.NewRequest(http.MethodGet, "/v1/version", nil)
	rr := httptest.NewRecorder()
	h.Serve(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if body["version"] != "1.2.3" {
		t.Errorf("version: got %q, want %q", body["version"], "1.2.3")
	}
	if body["commit"] != "abc1234" {
		t.Errorf("commit: got %q, want %q", body["commit"], "abc1234")
	}
}

func TestVersionHandler_DefaultValues(t *testing.T) {
	h := NewVersionHandler("dev", "unknown")

	req := httptest.NewRequest(http.MethodGet, "/v1/version", nil)
	rr := httptest.NewRecorder()
	h.Serve(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if body["version"] != "dev" {
		t.Errorf("version: got %q, want %q", body["version"], "dev")
	}
	if body["commit"] != "unknown" {
		t.Errorf("commit: got %q, want %q", body["commit"], "unknown")
	}
}