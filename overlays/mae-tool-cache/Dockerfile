# MAE — Modern AI Editor
# Multi-stage Dockerfile: base -> builder -> ci -> runtime
#
# Usage:
#   docker compose run --rm --build ci         # full CI pipeline
#   docker compose run --rm --build smoke      # quick binary smoke test
#   docker compose run --rm --build new-user   # clean-room first-run validation
#   docker compose run --rm --build dev        # interactive dev shell
#
# Benchmark overlay: the pinned upstream Dockerfile with BoringCache-backed
# sccache plus persistent Cargo registry, Git, and target cache mounts.

# ---------------------------------------------------------------------------
# Stage: base — shared Rust toolchain + system deps
# ---------------------------------------------------------------------------
ARG RUST_VERSION=1.95
FROM rust:${RUST_VERSION}-slim-bookworm AS base

ARG RUST_VERSION
ARG TARGETARCH
ARG SCCACHE_VERSION=v0.14.0
ENV CARGO_TARGET_DIR=/mae/target

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config make git clang curl \
    libfontconfig1-dev libfreetype6-dev \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && rustup component add rustfmt clippy

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) sccache_arch="x86_64" ;; \
      arm64) sccache_arch="aarch64" ;; \
      *) echo "unsupported sccache architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/${SCCACHE_VERSION}/sccache-${SCCACHE_VERSION}-${sccache_arch}-unknown-linux-musl.tar.gz" \
      | tar xz -C /tmp; \
    mv "/tmp/sccache-${SCCACHE_VERSION}-${sccache_arch}-unknown-linux-musl/sccache" /usr/local/bin/sccache; \
    chmod +x /usr/local/bin/sccache; \
    sccache --version

WORKDIR /mae

# --- Dependency cache layer ---
# Copy only manifests + lock, create dummy sources, build deps.
# Source-only changes won't invalidate this ~5 min compile.
COPY Cargo.toml Cargo.lock ./
COPY crates/core/Cargo.toml crates/core/Cargo.toml
COPY crates/renderer/Cargo.toml crates/renderer/Cargo.toml
COPY crates/gui/Cargo.toml crates/gui/Cargo.toml
COPY crates/scheme/Cargo.toml crates/scheme/Cargo.toml
COPY crates/lsp/Cargo.toml crates/lsp/Cargo.toml
COPY crates/dap/Cargo.toml crates/dap/Cargo.toml
COPY crates/ai/Cargo.toml crates/ai/Cargo.toml
COPY crates/mae/Cargo.toml crates/mae/Cargo.toml
COPY crates/shell/Cargo.toml crates/shell/Cargo.toml
COPY daemon/Cargo.toml daemon/Cargo.lock daemon/
COPY crates/canvas/Cargo.toml crates/canvas/Cargo.toml
COPY crates/babel/Cargo.toml crates/babel/Cargo.toml
COPY crates/export/Cargo.toml crates/export/Cargo.toml
COPY crates/snippets/Cargo.toml crates/snippets/Cargo.toml
COPY crates/format/Cargo.toml crates/format/Cargo.toml
COPY crates/make/Cargo.toml crates/make/Cargo.toml
COPY crates/lookup/Cargo.toml crates/lookup/Cargo.toml
COPY crates/spell/Cargo.toml crates/spell/Cargo.toml
COPY test_fixtures/Cargo.toml test_fixtures/Cargo.toml
COPY shared/kb/Cargo.toml shared/kb/Cargo.toml
COPY shared/sync/Cargo.toml shared/sync/Cargo.toml
COPY shared/mcp/Cargo.toml shared/mcp/Cargo.toml

# Create dummy source files so cargo can resolve the dependency graph
RUN mkdir -p crates/core/src && echo "" > crates/core/src/lib.rs && \
    mkdir -p crates/renderer/src && echo "" > crates/renderer/src/lib.rs && \
    mkdir -p crates/gui/src && echo "" > crates/gui/src/lib.rs && \
    mkdir -p crates/scheme/src && echo "" > crates/scheme/src/lib.rs && \
    mkdir -p crates/lsp/src && echo "" > crates/lsp/src/lib.rs && \
    mkdir -p crates/dap/src && echo "" > crates/dap/src/lib.rs && \
    mkdir -p crates/ai/src && echo "" > crates/ai/src/lib.rs && \
    mkdir -p crates/mae/src && echo "fn main() {}" > crates/mae/src/main.rs && \
    mkdir -p crates/shell/src && echo "" > crates/shell/src/lib.rs && \
    mkdir -p daemon/src && echo "fn main() {}" > daemon/src/main.rs && echo "" > daemon/src/lib.rs && \
    mkdir -p crates/canvas/src && echo "" > crates/canvas/src/lib.rs && \
    mkdir -p shared/kb/src && echo "" > shared/kb/src/lib.rs && \
    mkdir -p shared/sync/src && echo "" > shared/sync/src/lib.rs && \
    mkdir -p shared/mcp/src && echo "" > shared/mcp/src/lib.rs && \
    echo "fn main() {}" > shared/mcp/src/shim.rs && \
    mkdir -p crates/babel/src && echo "" > crates/babel/src/lib.rs && \
    mkdir -p crates/export/src && echo "" > crates/export/src/lib.rs && \
    mkdir -p crates/snippets/src && echo "" > crates/snippets/src/lib.rs && \
    mkdir -p crates/format/src && echo "" > crates/format/src/lib.rs && \
    mkdir -p crates/make/src && echo "" > crates/make/src/lib.rs && \
    mkdir -p crates/lookup/src && echo "" > crates/lookup/src/lib.rs && \
    mkdir -p crates/spell/src && echo "" > crates/spell/src/lib.rs && \
    mkdir -p test_fixtures/src && echo "" > test_fixtures/src/lib.rs

# Build dependencies only (will fail on our dummy sources, but deps get cached)
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=mae-cargo-registry-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,id=mae-cargo-git-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/mae/target,id=mae-cargo-target-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=secret,id=boringcache-tool-cache-env \
    . /run/secrets/boringcache-tool-cache-env && \
    export RUSTC_WRAPPER=sccache && \
    { cargo build --release --workspace --exclude mae-gui 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Stage: builder — full source compile
# ---------------------------------------------------------------------------
FROM base AS builder

# Copy real source (overwrites dummy stubs)
COPY . .

# Touch all source files so cargo knows they changed vs the dummy stubs
RUN find crates/ shared/ daemon/ test_fixtures/ -name '*.rs' -exec touch {} +

RUN --mount=type=cache,target=/usr/local/cargo/registry,id=mae-cargo-registry-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,id=mae-cargo-git-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/mae/target,id=mae-cargo-target-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=secret,id=boringcache-tool-cache-env \
    . /run/secrets/boringcache-tool-cache-env && \
    export RUSTC_WRAPPER=sccache && \
    { sccache --zero-stats >/dev/null 2>&1 || true; } && \
    cargo build --release --workspace --exclude mae-gui && \
    cd daemon && cargo build --release && \
    cd /mae && mkdir -p out && \
    cp target/release/mae out/mae && \
    cp target/release/mae-mcp-shim out/mae-mcp-shim && \
    cp target/release/mae-daemon out/mae-daemon && \
    echo BEGIN_BORINGCACHE_SCCACHE_STATS && \
    sccache --show-stats && \
    echo END_BORINGCACHE_SCCACHE_STATS

# ---------------------------------------------------------------------------
# Stage: ci — lint + test (build failure = image build failure)
# ---------------------------------------------------------------------------
FROM builder AS ci

RUN cargo fmt --all --check
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=mae-cargo-registry-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,id=mae-cargo-git-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/mae/target,id=mae-cargo-target-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=secret,id=boringcache-tool-cache-env \
    . /run/secrets/boringcache-tool-cache-env && \
    RUSTC_WRAPPER=sccache cargo clippy --workspace --all-targets --exclude mae-gui -- -D warnings
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=mae-cargo-registry-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,id=mae-cargo-git-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=cache,target=/mae/target,id=mae-cargo-target-${TARGETARCH}-rust-${RUST_VERSION},sharing=locked \
    --mount=type=secret,id=boringcache-tool-cache-env \
    . /run/secrets/boringcache-tool-cache-env && \
    RUSTC_WRAPPER=sccache cargo test --workspace --exclude mae-gui

# No CMD — this stage exists only to validate. `docker compose build ci` IS the test.

# ---------------------------------------------------------------------------
# Stage: runtime — minimal image for running mae
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates netcat-openbsd \
  && rm -rf /var/lib/apt/lists/*

# Non-root user (UID 1000 matches typical host user for volume mounts)
RUN useradd -m -u 1000 -s /bin/bash mae

# Pre-create XDG dirs, workspace, shared, and sync directories
RUN mkdir -p /home/mae/.config/mae /home/mae/.local/share/mae /home/mae/.local/state/mae \
    /sync /workspace /shared \
  && chown -R mae:mae /home/mae /sync /workspace /shared

COPY --from=builder /mae/out/mae /usr/local/bin/mae
COPY --from=builder /mae/out/mae-mcp-shim /usr/local/bin/mae-mcp-shim
COPY --from=builder /mae/out/mae-daemon /usr/local/bin/mae-daemon

# OCI labels
LABEL org.opencontainers.image.source="https://github.com/cuttlefisch/mae"
LABEL org.opencontainers.image.licenses="GPL-3.0-or-later"
LABEL org.opencontainers.image.description="MAE — Modern AI Editor"

USER mae
WORKDIR /home/mae

ENTRYPOINT ["mae"]
