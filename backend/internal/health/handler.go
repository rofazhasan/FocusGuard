package health

import (
	"encoding/json"
	"net/http"
	"time"
)

type Response struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
	Version   string `json:"version"`
}

func Handler(w http.ResponseWriter, r *http.Request) {
	resp := Response{
		Status:    "UP",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Version:   "1.0.0",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
