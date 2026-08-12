package main

import (
	"dagger/verified-download/internal/contract"
	"dagger/verified-download/internal/dagger"
)

// VerifiedDownload fetches immutable HTTPS content with an expected SHA-256 digest.
type VerifiedDownload struct{}

// Fetch returns a file only when Dagger verifies the expected SHA-256 digest.
func (VerifiedDownload) Fetch(
	url, sha256 string,
	name string, // +optional
) (*dagger.File, error) {
	url, checksum, name, err := contract.Request(url, sha256, name)
	if err != nil {
		return nil, err
	}
	return dag.HTTP(url, dagger.HTTPOpts{Name: name, Checksum: checksum}), nil
}
