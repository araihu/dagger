# generated

Typed generated-file drift checks for Dagger Engine v0.21.8.

Pass narrowly scoped committed and regenerated `Directory` values. `drift` returns a native Dagger `Changeset`; `assert-clean` returns stable per-path evidence. The module runs no generator itself, so consumers can pair it with Go, Node, templ, OpenAPI, or asset generation.

Pin the remote module to a full commit:

```sh
dagger -m github.com/araihu/dagger/modules/generated@<40-character-commit> call assert-clean \
  --committed=./generated --regenerated=./out/generated
```
