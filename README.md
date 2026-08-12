# Araihu Dagger runner

Pinned GitHub Actions runner image for Araihu's Hostinger executor.

The image extends the existing Ubuntu Noble runner and adds Dagger CLI
`v0.21.8`. Dagger Engine runs separately on the host; jobs connect through
`_EXPERIMENTAL_DAGGER_RUNNER_HOST`.

## Image

```text
ghcr.io/araihu/dagger:0.21.8-runner-2.336.0
```

Production consumers should pin the published manifest digest, not a mutable
tag. CLI and Engine versions must match.

## Build inputs

- Runner: `2.336.0-ubuntu-noble`, pinned by digest.
- Dagger CLI: `v0.21.8`, verified against the official release SHA-256.
- Platform: `linux/amd64`.

GitHub Actions publishes SBOM and provenance attestations with each image.
