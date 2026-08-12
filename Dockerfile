# syntax=docker/dockerfile:1.7

FROM ghcr.io/myoung34/docker-github-actions-runner:2.336.0-ubuntu-noble@sha256:2840401868e84feb8e5a45d4ecc1009d66d8b21e7906324cf2a052c42ac79189

ARG DAGGER_VERSION=0.21.8
ARG DAGGER_SHA256=53e226c7da8fb75171e58c35759d736d961ce8b3a12db0baa7b7107954fccc5a

USER root

RUN curl --fail --silent --show-error --location \
      "https://github.com/dagger/dagger/releases/download/v${DAGGER_VERSION}/dagger_v${DAGGER_VERSION}_linux_amd64.tar.gz" \
      --output /tmp/dagger.tar.gz \
    && printf '%s  %s\n' "${DAGGER_SHA256}" /tmp/dagger.tar.gz | sha256sum --check --strict \
    && tar --extract --gzip --file /tmp/dagger.tar.gz --directory /usr/local/bin dagger \
    && chmod 0755 /usr/local/bin/dagger \
    && rm /tmp/dagger.tar.gz \
    && dagger version | grep --fixed-strings "dagger v${DAGGER_VERSION}"

LABEL org.opencontainers.image.title="Araihu Dagger runner" \
      org.opencontainers.image.description="GitHub Actions runner with a pinned Dagger CLI" \
      org.opencontainers.image.source="https://github.com/araihu/dagger" \
      org.opencontainers.image.licenses="MIT AND Apache-2.0"
