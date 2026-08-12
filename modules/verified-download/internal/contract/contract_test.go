package contract

import "testing"

func TestRequestNormalizesDigest(t *testing.T) {
	t.Parallel()

	digest := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	url, gotDigest, name, err := Request("https://example.com/tool", digest, "tool")
	if err != nil || url != "https://example.com/tool" || gotDigest != "sha256:"+digest || name != "tool" {
		t.Fatalf("Request() = %q, %q, %q, %v", url, gotDigest, name, err)
	}
}

func TestRequestRejectsUnsafeInputs(t *testing.T) {
	t.Parallel()

	digest := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	for _, test := range []struct {
		url, digest, name string
	}{
		{"http://example.com/tool", digest, "tool"},
		{"https://token@example.com/tool", digest, "tool"},
		{"https://example.com/tool", "bad", "tool"},
		{"https://example.com/tool", digest, "../tool"},
		{"https://example.com/tool", digest, "/"},
	} {
		if _, _, _, err := Request(test.url, test.digest, test.name); err == nil {
			t.Fatalf("expected rejection for %#v", test)
		}
	}
}
