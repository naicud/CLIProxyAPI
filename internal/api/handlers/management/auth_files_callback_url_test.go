package management

import (
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/router-for-me/CLIProxyAPI/v6/internal/config"
)

func TestManagementCallbackURLFromRequest_UsesPublicRequestHost(t *testing.T) {
	gin.SetMode(gin.TestMode)

	rec := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(rec)
	req := httptest.NewRequest("GET", "http://localhost:9999/v0/management/gemini-cli-auth-url?is_webui=true", nil)
	req.Host = "localhost:9999"
	ctx.Request = req

	h := NewHandlerWithoutConfigFilePath(&config.Config{Port: 8317}, nil)

	targetURL, err := h.managementCallbackURLFromRequest(ctx, "/google/callback")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if targetURL != "http://localhost:9999/google/callback" {
		t.Fatalf("expected public callback URL, got %q", targetURL)
	}
}

func TestManagementCallbackURLFromRequest_FallsBackToConfiguredPort(t *testing.T) {
	gin.SetMode(gin.TestMode)

	rec := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(rec)
	req := httptest.NewRequest("GET", "/v0/management/gemini-cli-auth-url?is_webui=true", nil)
	req.Host = ""
	ctx.Request = req

	h := NewHandlerWithoutConfigFilePath(&config.Config{Port: 8317}, nil)

	targetURL, err := h.managementCallbackURLFromRequest(ctx, "/google/callback")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if targetURL != "http://127.0.0.1:8317/google/callback" {
		t.Fatalf("expected fallback callback URL, got %q", targetURL)
	}
}

func TestManagementRequestURL_UsesForwardedProto(t *testing.T) {
	gin.SetMode(gin.TestMode)

	rec := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(rec)
	req := httptest.NewRequest("GET", "http://localhost/v0/management/gemini-cli-auth-url?is_webui=true", nil)
	req.Host = "proxy.example.com"
	req.Header.Set("X-Forwarded-Proto", "https")
	ctx.Request = req

	targetURL, ok := managementRequestURL(ctx, "/google/callback")
	if !ok {
		t.Fatal("expected request URL to be derived from forwarded headers")
	}
	if targetURL != "https://proxy.example.com/google/callback" {
		t.Fatalf("expected forwarded callback URL, got %q", targetURL)
	}
}
