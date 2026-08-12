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
			t.Errorf("public Node primitive contains forbidden cache selector %q", forbidden)
		}
	}
}

func TestSmokeExecutesPinnedToolchain(t *testing.T) {
	source, err := os.ReadFile("../../main.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(source), `func (m *NodeCI) Smoke() *dagger.Container`) ||
		!strings.Contains(string(source), `WithExec([]string{"node", "--version"})`) {
		t.Fatal("Node smoke must execute the pinned toolchain in Base")
	}
}

func TestWorkspaceRejectsEscape(t *testing.T) {
	t.Parallel()

	if _, err := Workspace("../../outside"); err == nil {
		t.Fatal("expected traversal to be rejected")
	}
}

func TestRunArgsDoesNotUseShell(t *testing.T) {
	t.Parallel()

	want := []string{"npm", "run", "test", "--", "--watch=false"}
	got, err := RunArgs("test", []string{"--watch=false"})
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("RunArgs() = %#v, %v; want %#v", got, err, want)
	}
}
