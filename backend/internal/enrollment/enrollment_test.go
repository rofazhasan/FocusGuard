package enrollment

import (
	"strings"
	"testing"
)

func TestPairingCodeFormat(t *testing.T) {
	code := generatePairingCode()
	if !strings.HasPrefix(code, "FG-") {
		t.Errorf("Expected pairing code to start with FG-, got %s", code)
	}
	if len(code) != 9 { // "FG-" (3) + 6 chars = 9
		t.Errorf("Expected pairing code length 9, got %d (%s)", len(code), code)
	}
}
