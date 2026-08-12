# Araihu Dagger

Shared Dagger foundation for Araihu pipelines.

Repository surfaces:

- `images/runner`: thin Hostinger runner image containing Dagger CLI.
- `modules`: reusable CI modules and toolchains shared by Araihu repositories.

Build tools belong inside Dagger containers. The runner image remains minimal:
Dagger CLI `v0.21.8` plus connection to the separately managed host Engine.

Remote module consumers must pin the full reviewed Git commit, for example
`github.com/araihu/dagger/modules/go@<40-character-commit>`. The shared modules
target Dagger Engine v0.21.8 and keep project-specific publish/deploy orchestration
in each consuming repository.

## Image

```text
ghcr.io/araihu/dagger:0.21.8-runner-2.336.0
```

Production consumers should pin the published manifest digest, not a mutable
tag. CLI and Engine versions must match.

## Runner build inputs

- Runner: `2.336.0-ubuntu-noble`, pinned by digest.
- Dagger CLI: `v0.21.8`, verified against the official release SHA-256.
- Platform: `linux/amd64`.

GitHub Actions publishes SBOM and provenance attestations with each image.
