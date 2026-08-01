# syntax=docker/dockerfile:1.7
ARG RUST_VERSION=1.95
ARG ALPINE_VERSION=3.23

FROM --platform=$BUILDPLATFORM lukemathwalker/cargo-chef:latest-rust-${RUST_VERSION}-alpine${ALPINE_VERSION} AS chef
WORKDIR /app
RUN apk add --no-cache musl-dev pkgconfig

FROM --platform=$BUILDPLATFORM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM --platform=$BUILDPLATFORM chef AS builder
ARG PROFILE=release
ARG TARGETPLATFORM
ARG LIBC=musl
ARG IGGY_CI_BUILD
ARG SCCACHE_VERSION=v0.14.0
ENV IGGY_CI_BUILD=${IGGY_CI_BUILD}
ENV CARGO_INCREMENTAL=0

RUN set -eux; \
    apk add --no-cache bash curl tar; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64) sccache_arch="x86_64" ;; \
      aarch64) sccache_arch="aarch64" ;; \
      *) echo "unsupported sccache architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/${SCCACHE_VERSION}/sccache-${SCCACHE_VERSION}-${sccache_arch}-unknown-linux-musl.tar.gz" | tar xz -C /tmp; \
    mv "/tmp/sccache-${SCCACHE_VERSION}-${sccache_arch}-unknown-linux-musl/sccache" /usr/local/bin/sccache; \
    chmod +x /usr/local/bin/sccache; \
    sccache --version

RUN apk add --no-cache zig make autoconf automake libtool pkgconfig hwloc-dev xz-dev xz-static nodejs npm && \
    cargo install cargo-zigbuild --version '=0.22.1' --locked && \
    rustup target add \
    x86_64-unknown-linux-musl \
    aarch64-unknown-linux-musl \
    x86_64-unknown-linux-gnu \
    aarch64-unknown-linux-gnu

ENV PKG_CONFIG_ALLOW_CROSS=1

COPY --from=planner /app/recipe.json recipe.json

RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry-${TARGETPLATFORM}-${LIBC} \
    --mount=type=cache,target=/usr/local/cargo/git,id=cargo-git-${TARGETPLATFORM}-${LIBC} \
    --mount=type=cache,target=/app/target,id=cargo-target-${TARGETPLATFORM}-${LIBC} \
    --mount=type=secret,id=boringcache-tool-cache-env \
    set -eux; \
    . /run/secrets/boringcache-tool-cache-env; \
    export RUSTC_WRAPPER=sccache; \
    case "$TARGETPLATFORM:$LIBC" in \
    "linux/amd64:musl")  RUST_TARGET="x86_64-unknown-linux-musl" ;; \
    "linux/arm64:musl")  RUST_TARGET="aarch64-unknown-linux-musl" ;; \
    "linux/amd64:glibc") RUST_TARGET="x86_64-unknown-linux-gnu"  ;; \
    "linux/arm64:glibc") RUST_TARGET="aarch64-unknown-linux-gnu" ;; \
    *) echo "Unsupported $TARGETPLATFORM/$LIBC" && exit 1 ;; \
    esac && \
    if [ "$PROFILE" = "debug" ]; then \
    cargo chef cook --recipe-path recipe.json --target ${RUST_TARGET} --zigbuild \
      -p server -p iggy-cli; \
    else \
    cargo chef cook --recipe-path recipe.json --target ${RUST_TARGET} --zigbuild --release \
      -p server -p iggy-cli; \
    fi

COPY . .

RUN npm --prefix web ci && npm --prefix web run build:static

RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry-${TARGETPLATFORM}-${LIBC} \
    --mount=type=cache,target=/usr/local/cargo/git,id=cargo-git-${TARGETPLATFORM}-${LIBC} \
    --mount=type=cache,target=/app/target,id=cargo-target-${TARGETPLATFORM}-${LIBC} \
    --mount=type=secret,id=boringcache-tool-cache-env \
    set -eux; \
    . /run/secrets/boringcache-tool-cache-env; \
    export RUSTC_WRAPPER=sccache; \
    sccache --zero-stats >/dev/null 2>&1 || true; \
    case "$TARGETPLATFORM:$LIBC" in \
    "linux/amd64:musl")  RUST_TARGET="x86_64-unknown-linux-musl" ;; \
    "linux/arm64:musl")  RUST_TARGET="aarch64-unknown-linux-musl" ;; \
    "linux/amd64:glibc") RUST_TARGET="x86_64-unknown-linux-gnu"  ;; \
    "linux/arm64:glibc") RUST_TARGET="aarch64-unknown-linux-gnu" ;; \
    *) echo "Unsupported $TARGETPLATFORM/$LIBC" && exit 1 ;; \
    esac && \
    if [ "$PROFILE" = "debug" ]; then \
    cargo zigbuild --locked --target ${RUST_TARGET} --bin iggy-server --bin iggy && \
    cp /app/target/${RUST_TARGET}/debug/iggy-server /app/iggy-server && \
    cp /app/target/${RUST_TARGET}/debug/iggy /app/iggy; \
    else \
    cargo zigbuild --locked --target ${RUST_TARGET} --bin iggy-server --bin iggy --release && \
    cp /app/target/${RUST_TARGET}/release/iggy-server /app/iggy-server && \
    cp /app/target/${RUST_TARGET}/release/iggy /app/iggy; \
    fi; \
    echo BEGIN_BORINGCACHE_SCCACHE_STATS; \
    sccache --show-stats; \
    echo END_BORINGCACHE_SCCACHE_STATS

RUN TARGET="$(uname -m)-unknown-linux-musl" && \
    curl -sSfL "https://github.com/EmbarkStudios/cargo-about/releases/download/0.9.0/cargo-about-0.9.0-${TARGET}.tar.gz" \
      | tar -xz -C /usr/local/bin --strip-components=1 "cargo-about-0.9.0-${TARGET}/cargo-about" && \
    ./scripts/ci/third-party-licenses.sh --generate \
      --manifest core/server/Cargo.toml \
      --manifest core/cli/Cargo.toml \
      --manifest web \
      --output /app/LICENSE-binary

FROM debian:trixie-slim AS runtime
ARG TARGETPLATFORM
ARG PROFILE=release
ARG LIBC=musl
WORKDIR /app
RUN apt-get update && apt-get install -y \
    libhwloc15 \
    libudev1 \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/iggy-server /usr/local/bin/iggy-server
COPY --from=builder /app/iggy        /usr/local/bin/iggy
COPY --from=builder /app/LICENSE-binary /usr/share/doc/iggy/LICENSE-binary
COPY LICENSE NOTICE /usr/share/doc/iggy/
RUN echo "Iggy server built from source for ${TARGETPLATFORM:-linux/amd64} (${PROFILE}, ${LIBC})"
ENTRYPOINT ["iggy-server"]
