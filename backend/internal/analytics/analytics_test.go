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

func TestCalculateIntervalUnion(t *testing.T) {
	// Scenario:
	// Windows: 10:00 to 10:30 (1800s)
	// Android: 10:10 to 10:40 (1800s)
	// macOS:   10:20 to 10:25 (300s)
	// Total Raw Sum: 3900s (65m)
	// True Union: 10:00 to 10:40 = 2400s (40m)
	intervals := []TimeInterval{
		{Start: 1000, End: 2800}, // 1800s
		{Start: 1600, End: 3400}, // 1800s
		{Start: 2200, End: 2500}, // 300s
	}

	result := CalculateIntervalUnion(intervals)

	if result.RawSumSeconds != 3900 {
		t.Errorf("expected raw sum 3900s, got %d", result.RawSumSeconds)
	}
	if result.UnionSeconds != 2400 {
		t.Errorf("expected union 2400s, got %d", result.UnionSeconds)
	}
	if len(result.MergedIntervals) != 1 {
		t.Errorf("expected 1 merged interval, got %d", len(result.MergedIntervals))
	}
	if result.MergedIntervals[0].Start != 1000 || result.MergedIntervals[0].End != 3400 {
		t.Errorf("expected merged [1000, 3400], got [%d, %d]", result.MergedIntervals[0].Start, result.MergedIntervals[0].End)
	}
}

