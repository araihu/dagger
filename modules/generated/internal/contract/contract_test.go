package contract

import (
	"strings"
	"testing"
)

func TestDriftError(t *testing.T) {
	t.Parallel()

	if err := DriftError(nil, nil, nil); err != nil {
		t.Fatalf("clean directories returned %v", err)
	}
	err := DriftError([]string{"z.go"}, []string{"a.go"}, []string{"old.go"})
	if err == nil || !strings.Contains(err.Error(), "+z.go, -old.go, ~a.go") {
		t.Fatalf("unexpected drift error: %v", err)
	}
}
