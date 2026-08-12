package main

import (
	"dagger/go-ci/internal/contract"
	"dagger/go-ci/internal/dagger"
)

const goImage = "docker.io/library/golang:1.26.5-bookworm@sha256:53eeac89074db483fdf0ab3be1df32bf6e47562263d2d0d6baa7f26acb4957dd"

// GoCI provides side-effect-free Go build and verification primitives.
type GoCI struct {
	Source *dagger.Directory
}

func New(
	// +defaultPath="/"
	// +optional
	source *dagger.Directory,
) *GoCI {
	return &GoCI{Source: source}
}

// Base returns the pinned Go toolchain without persistent cross-call caches.
func (m *GoCI) Base() *dagger.Container {
	return dag.Container().
		From(goImage).
		WithEnvVariable("GOMODCACHE", "/go/pkg/mod").
		WithEnvVariable("GOCACHE", "/root/.cache/go-build").
		WithMountedDirectory("/src", m.Source)
}

// Test downloads declared modules and runs go test for the selected module directory.
func (m *GoCI) Test(
	module string, // +optional
	packages []string, // +optional
	race bool, // +optional
) (*dagger.Container, error) {
	workdir, err := contract.Workspace(module)
	if err != nil {
		return nil, err
	}
	return m.Base().WithWorkdir(workdir).
		WithExec([]string{"go", "mod", "download"}).
		WithExec(contract.TestArgs(packages, race)), nil
}

// Vet downloads declared modules and runs go vet for the selected packages.
func (m *GoCI) Vet(
	module string, // +optional
	packages []string, // +optional
) (*dagger.Container, error) {
	workdir, err := contract.Workspace(module)
	if err != nil {
		return nil, err
	}
	args := append([]string{"go", "vet"}, contract.Packages(packages)...)
	return m.Base().WithWorkdir(workdir).
		WithExec([]string{"go", "mod", "download"}).
		WithExec(args), nil
}

// Generate runs go generate and returns the resulting source snapshot for drift comparison.
func (m *GoCI) Generate(
	module string, // +optional
	packages []string, // +optional
) (*dagger.Directory, error) {
	workdir, err := contract.Workspace(module)
	if err != nil {
		return nil, err
	}
	args := append([]string{"go", "generate"}, contract.Packages(packages)...)
	return m.Base().WithWorkdir(workdir).WithExec(args).Directory("/src"), nil
}

// Build compiles one package with reproducible paths and returns the binary.
func (m *GoCI) Build(module, pkg, output string) (*dagger.File, error) {
	workdir, err := contract.Workspace(module)
	if err != nil {
		return nil, err
	}
	output, err = contract.OutputName(output)
	if err != nil {
		return nil, err
	}
	if pkg == "" {
		pkg = "."
	}
	return m.Base().WithWorkdir(workdir).
		WithExec([]string{"go", "mod", "download"}).
		WithDirectory("/out", dag.Directory()).
		WithExec([]string{"go", "build", "-trimpath", "-o", "/out/" + output, pkg}).
		File("/out/" + output), nil
}
