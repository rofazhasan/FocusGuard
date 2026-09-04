package pairing

import (
	"strings"
	"testing"
)

func TestGenerateHumanCode(t *testing.T) {
	for i := 0; i < 20; i++ {
		code := generateHumanCode()
		if !strings.HasPrefix(code, "FG-") {
			t.Errorf("Expected code to start with 'FG-', got: %s", code)
		}
		if len(code) != 9 { // "FG-" + 6 chars
			t.Errorf("Expected length 9, got %d for code: %s", len(code), code)
		}

		// Check for ambiguous characters (0, O, 1, I)
		if strings.ContainsAny(code, "01OI") {
			t.Errorf("Code contains ambiguous characters: %s", code)
		}
	}
}

func TestHashCode(t *testing.T) {
	code := "FG-A2B3C4"
	hash1 := hashCode(code)
	hash2 := hashCode("  fg-a2b3c4  ") // Case-insensitive and trimmed

	if hash1 == "" {
		t.Errorf("Hash must not be empty")
	}

	if hash1 != hash2 {
		t.Errorf("Hash must normalize case and whitespace: %s vs %s", hash1, hash2)
	}
}
