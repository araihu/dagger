# verified-download

Immutable HTTPS downloads for Dagger Engine v0.21.8.

The module rejects non-HTTPS URLs and malformed SHA-256 values, then delegates content verification to Dagger's native `HTTP(checksum:)` operation. It does not execute, unpack, publish, or deploy downloaded content.

Pin the remote module to a full commit:

```sh
dagger -m github.com/araihu/dagger/modules/verified-download@<40-character-commit> call fetch \
  --url=https://example.com/tool --sha256=<64-hex-character-sha256>
```
