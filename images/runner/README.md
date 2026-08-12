# Runner image

Thin GitHub Actions runner image for Araihu's Hostinger executor.

It contains only the pinned Dagger CLI needed to connect to the host-managed
Engine. Build, test, release, and service toolchains belong inside Dagger
containers, not this runner image.

Published tags:

```text
ghcr.io/araihu/dagger:0.21.8
ghcr.io/araihu/dagger:0.21.8-runner-2.336.0
```

Production consumers must use the immutable manifest digest emitted by the
publish workflow.
