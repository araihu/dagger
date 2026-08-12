# go-ci

Reusable Go verification primitives for Dagger Engine v0.21.8.

- Go 1.26.5 image pinned by digest.
- No persistent `CacheVolume`; consumers cannot accidentally share mutable PR state.
- `Test`, `Vet`, `Generate`, and `Build` accept typed Dagger inputs/outputs.
- No registry, release, deployment, or secret side effects.

Call from a consumer using a full immutable commit:

```sh
dagger -m github.com/araihu/dagger/modules/go@<40-character-commit> call test \
  --source=.
```
