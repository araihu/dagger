package main

import (
	"dagger/node-ci/internal/contract"
	"dagger/node-ci/internal/dagger"
)

const nodeImage = "docker.io/library/node:24.12.0-bookworm-slim@sha256:7326fb2dbdce998edd72140946851be64ef4a643e8715e138ca467e8e9d92c99"

// NodeCI provides npm install and script primitives without publication side effects.
type NodeCI struct {
	Source *dagger.Directory
}

func New(
	// +defaultPath="/"
	// +optional
	source *dagger.Directory,
) *NodeCI {
	return &NodeCI{Source: source}
}

// Base returns the pinned Node toolchain without persistent cross-call caches.
func (m *NodeCI) Base() *dagger.Container {
	return dag.Container().
		From(nodeImage).
		WithEnvVariable("npm_config_cache", "/root/.npm").
		WithMountedDirectory("/src", m.Source)
}

// Install runs npm ci. Set ignoreScripts when dependency lifecycle scripts are not required.
func (m *NodeCI) Install(
	workspace string, // +optional
	ignoreScripts bool, // +optional
) (*dagger.Container, error) {
	workdir, err := contract.Workspace(workspace)
	if err != nil {
		return nil, err
	}
	return m.Base().WithWorkdir(workdir).WithExec(contract.InstallArgs(ignoreScripts)), nil
}

// Run installs dependencies and executes one package.json script without a shell.
func (m *NodeCI) Run(
	workspace, script string,
	args []string, // +optional
	ignoreScripts bool, // +optional
) (*dagger.Container, error) {
	container, err := m.Install(workspace, ignoreScripts)
	if err != nil {
		return nil, err
	}
	command, err := contract.RunArgs(script, args)
	if err != nil {
		return nil, err
	}
	return container.WithExec(command), nil
}
