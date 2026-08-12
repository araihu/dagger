# node-ci

Reusable Node/npm primitives for Dagger Engine v0.21.8.

- Node 24.12.0 image pinned by digest.
- No persistent `CacheVolume`; consumers cannot accidentally share mutable PR state.
- `node_modules` is not a mutable shared cache; Dagger layer caching owns installed output.
- Scripts run through argv, not a shell.
- No npm publication, registry login, release, or deployment functions.

Pin the remote module to a full commit:

```sh
dagger -m github.com/araihu/dagger/modules/node@<40-character-commit> call run \
  --source=. \
  --script=test
```
