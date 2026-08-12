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

func TestWorkflowBaseContractUsesStructuralContainerQuery(t *testing.T) {
	workflow, err := os.ReadFile("../../../../.github/workflows/modules.yml")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(workflow)
	if !strings.Contains(contents, `call base id`) {
		t.Fatal("smallest runtime contract must resolve the transformed base container ID")
	}
	if strings.Contains(contents, `call base stdout`) {
		t.Fatal("base container has no command; stdout would fail at runtime")
	}
	if strings.Contains(contents, `call base image-ref`) {
		t.Fatal("image-ref is invalid after base applies env and mount transforms")
	}
	if !strings.Contains(contents, `test -n "$container_id"`) {
		t.Fatal("runtime contract must reject an empty container ID")
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
