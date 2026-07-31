# syntax=docker/dockerfile:1.7

ARG RUST_VERSION=1.91

# The Dioxus output is WASM and static assets, so build it once on the native
# runner instead of installing the CLI and compiling it again under QEMU.
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-bookworm AS ui
WORKDIR /src
ARG BUILDARCH
ARG SCCACHE_VERSION=0.16.0
ARG SCCACHE_SHA256_AMD64=aec995a83ad3dff3d14b6314e08858b7b73d35ca85a5bcf3d3a9ec07dee35588
ARG SCCACHE_SHA256_ARM64=f73a5c39f96bb6ebb89cc7915cf182260d4cbf30765322c5e793d0fe8bd80784

RUN apt-get update && apt-get install -y --no-install-recommends \
      binaryen \
      ca-certificates \
      curl \
      pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add wasm32-unknown-unknown

RUN set -eux; \
    case "$(uname -m)" in \
      x86_64) sccache_target=x86_64-unknown-linux-musl; sccache_sha256="$SCCACHE_SHA256_AMD64" ;; \
      aarch64) sccache_target=aarch64-unknown-linux-musl; sccache_sha256="$SCCACHE_SHA256_ARM64" ;; \
      *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    sccache_archive="sccache-v${SCCACHE_VERSION}-${sccache_target}.tar.gz"; \
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/${sccache_archive}" -o "/tmp/${sccache_archive}"; \
    printf '%s  %s\n' "$sccache_sha256" "/tmp/${sccache_archive}" | sha256sum -c -; \
    tar -xzf "/tmp/${sccache_archive}" -C /tmp; \
    install -m 0755 "/tmp/sccache-v${SCCACHE_VERSION}-${sccache_target}/sccache" /usr/local/bin/sccache; \
    rm -rf "/tmp/${sccache_archive}" "/tmp/sccache-v${SCCACHE_VERSION}-${sccache_target}"; \
    sccache --version

RUN --mount=type=cache,target=/usr/local/cargo/registry,id=proteus-cargo-registry-${BUILDARCH},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,id=proteus-cargo-git-${BUILDARCH},sharing=locked \
    --mount=type=secret,id=boringcache-tool-cache-env \
    set -eux; \
    . /run/secrets/boringcache-tool-cache-env; \
    export RUSTC_WRAPPER=sccache; \
    cargo install dioxus-cli --version 0.7.9 --locked

COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=proteus-cargo-registry-${BUILDARCH},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,id=proteus-cargo-git-${BUILDARCH},sharing=locked \
    --mount=type=cache,target=/src/target,id=proteus-target-ui-${BUILDARCH},sharing=locked \
    --mount=type=secret,id=boringcache-tool-cache-env \
    set -eux; \
    . /run/secrets/boringcache-tool-cache-env; \
    export RUSTC_WRAPPER=sccache; \
    sccache --zero-stats >/dev/null 2>&1 || true; \
    dx build -p proteus-ui --platform web --release; \
    mkdir -p crates/proteus-ui/dist; \
    cp -a target/dx/proteus-ui/release/web/public/. crates/proteus-ui/dist/; \
    echo BEGIN_BORINGCACHE_SCCACHE_STATS; \
    sccache --show-stats; \
    echo END_BORINGCACHE_SCCACHE_STATS

FROM rust:${RUST_VERSION}-bookworm AS builder
WORKDIR /src
ARG TARGETARCH
ARG SCCACHE_VERSION=0.16.0
ARG SCCACHE_SHA256_AMD64=aec995a83ad3dff3d14b6314e08858b7b73d35ca85a5bcf3d3a9ec07dee35588
ARG SCCACHE_SHA256_ARM64=f73a5c39f96bb6ebb89cc7915cf182260d4cbf30765322c5e793d0fe8bd80784

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      libssl-dev \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "$(uname -m)" in \
      x86_64) sccache_target=x86_64-unknown-linux-musl; sccache_sha256="$SCCACHE_SHA256_AMD64" ;; \
      aarch64) sccache_target=aarch64-unknown-linux-musl; sccache_sha256="$SCCACHE_SHA256_ARM64" ;; \
      *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    sccache_archive="sccache-v${SCCACHE_VERSION}-${sccache_target}.tar.gz"; \
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/${sccache_archive}" -o "/tmp/${sccache_archive}"; \
    printf '%s  %s\n' "$sccache_sha256" "/tmp/${sccache_archive}" | sha256sum -c -; \
    tar -xzf "/tmp/${sccache_archive}" -C /tmp; \
    install -m 0755 "/tmp/sccache-v${SCCACHE_VERSION}-${sccache_target}/sccache" /usr/local/bin/sccache; \
    rm -rf "/tmp/${sccache_archive}" "/tmp/sccache-v${SCCACHE_VERSION}-${sccache_target}"; \
    sccache --version

COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY --from=ui /src/crates/proteus-ui/dist ./crates/proteus-ui/dist

RUN --mount=type=cache,target=/usr/local/cargo/registry,id=proteus-cargo-registry-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,id=proteus-cargo-git-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/src/target,id=proteus-target-controller-${TARGETARCH},sharing=locked \
    --mount=type=secret,id=boringcache-tool-cache-env \
    set -eux; \
    . /run/secrets/boringcache-tool-cache-env; \
    export RUSTC_WRAPPER=sccache; \
    sccache --zero-stats >/dev/null 2>&1 || true; \
    cargo build --release -p proteus-controller; \
    cp target/release/proteus-controller /src/proteus-controller; \
    echo BEGIN_BORINGCACHE_SCCACHE_STATS; \
    sccache --show-stats; \
    echo END_BORINGCACHE_SCCACHE_STATS

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=builder /src/proteus-controller /usr/local/bin/proteus-controller
USER nonroot:nonroot
EXPOSE 8080
ENV PROTEUS_API_ADDR=0.0.0.0:8080
ENTRYPOINT ["/usr/local/bin/proteus-controller"]
