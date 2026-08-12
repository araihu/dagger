package main

import (
	"context"
	"dagger/generated/internal/contract"
	"dagger/generated/internal/dagger"
)

// Generated compares committed and regenerated directory snapshots.
type Generated struct{}

// Drift returns the structured changes from committed to regenerated content.
func (Generated) Drift(committed, regenerated *dagger.Directory) *dagger.Changeset {
	return regenerated.Changes(committed)
}

// AssertClean fails with stable per-path evidence when generated content changed.
func (m Generated) AssertClean(ctx context.Context, committed, regenerated *dagger.Directory) error {
	changes := m.Drift(committed, regenerated)
	empty, err := changes.IsEmpty(ctx)
	if err != nil || empty {
		return err
	}
	added, err := changes.AddedPaths(ctx)
	if err != nil {
		return err
	}
	modified, err := changes.ModifiedPaths(ctx)
	if err != nil {
		return err
	}
	removed, err := changes.RemovedPaths(ctx)
	if err != nil {
		return err
	}
	return contract.DriftError(added, modified, removed)
}
