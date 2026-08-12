package analytics

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/internal/middleware"
)

func TestDailyAnalyticsZeroState(t *testing.T) {
	handler := NewHandler(nil)

	req := httptest.NewRequest("GET", "/api/v1/analytics/daily", nil)
	ctx := context.WithValue(req.Context(), middleware.UserContextKey, &auth.Claims{
		UserID: uuid.New(),
		Email:  "test@focusguard.io",
	})
	req = req.WithContext(ctx)

	w := httptest.NewRecorder()
	handler.GetDailyAnalytics(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected status 200 OK, got %d", w.Code)
	}

	var resp DailyAnalyticsResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.BudgetTotalMinutes != 90 {
		t.Errorf("expected default budget 90 min, got %d", resp.BudgetTotalMinutes)
	}
	if resp.ServerTimestamp <= 0 {
		t.Errorf("expected valid server timestamp, got %d", resp.ServerTimestamp)
	}
}

func TestWeeklyAnalyticsZeroState(t *testing.T) {
	handler := NewHandler(nil)

	req := httptest.NewRequest("GET", "/api/v1/analytics/weekly", nil)
	ctx := context.WithValue(req.Context(), middleware.UserContextKey, &auth.Claims{
		UserID: uuid.New(),
		Email:  "test@focusguard.io",
	})
	req = req.WithContext(ctx)

	w := httptest.NewRecorder()
	handler.GetWeeklyAnalytics(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected status 200 OK, got %d", w.Code)
	}

	var resp WeeklyAnalyticsResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.ServerTimestamp <= 0 {
		t.Errorf("expected valid server timestamp, got %d", resp.ServerTimestamp)
	}
}
