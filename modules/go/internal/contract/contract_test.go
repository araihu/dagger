package contract

import (
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestPublicPrimitiveHasNoPersistentCacheSelector(t *testing.T) {
	source, err := os.ReadFile("../../main.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"CacheVolume", "WithMountedCache", "CacheNamespace", "TrustDomain", "cacheNamespace", "trustDomain"} {
		if strings.Contains(string(source), forbidden) {
			t.Errorf("public Go primitive contains forbidden cache selector %q", forbidden)
		}
	}
}

func TestWorkspaceRejectsEscape(t *testing.T) {
	t.Parallel()

	if _, err := Workspace("../outside"); err == nil {
		t.Fatal("expected traversal to be rejected")
	}
	if got, err := Workspace("site"); err != nil || got != "/src/site" {
		t.Fatalf("Workspace(site) = %q, %v", got, err)
	}
}

func TestTestArgs(t *testing.T) {
	t.Parallel()

	want := []string{"go", "test", "-race", "./..."}
	if got := TestArgs(nil, true); !reflect.DeepEqual(got, want) {
		t.Fatalf("TestArgs() = %#v, want %#v", got, want)
	}
}

func TestOutputNameRejectsPath(t *testing.T) {
	t.Parallel()

	for _, output := range []string{"", "/", "bin/app", `bin\\app`} {
		if _, err := OutputName(output); err == nil {
			t.Fatalf("expected %q to be rejected", output)
		}
	}
}
