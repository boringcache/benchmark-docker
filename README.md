# docker-cache-proofs

Public benchmark runner for comparing Docker and build caches on real upstream projects.

Each case pins an upstream repository and source revision so fresh and rolling runs remain reproducible.

## Source Model

- Docker cases live in [`cases/`](cases/).
- Cases use upstream Dockerfiles and build contexts unless an explicit benchmark overlay is part of the case.

## What It Measures

Docker cases compare:

- GitHub Actions Cache
- BoringCache's CLI-managed BuildKit backend

Fresh runs seed an isolated cache from the pinned source. Rolling runs build a later pinned revision against the same stable cache scope.

Rust cases that declare a Cargo target cache mount can also run a paired target
proof. The ordinary BoringCache lane remains the product control. The target
lane enables the managed BuildKit cache-mount offloader, keeps an independent
cache scope, and records the target archive's compressed bytes, logical bytes,
file count, and rolling growth. Iggy and Wormhole currently expose this proof;
other cases fail early rather than silently running without target evidence.

Run an ordered pure-versus-target series with:

```sh
./scripts/dispatch-proof-series.sh \
  --case iggy-rust-server \
  --compare-rust-target
```

The target state is only a performance input. Builds must still be correct from
an empty mount because BuildKit may garbage-collect native cache mounts.
GitHub's `type=gha` exporter does not preserve cache-mount contents, so the
ordinary GHA lane runs once as the external-cache control; the target variant
adds only the isolated BoringCache offload lane.

BoringCache has one Docker cache product path in these proofs. The CLI owns the
builder and emits the native `type=boringcache` cache configuration; registry
cache and alternate-backend benchmark lanes have been retired.

## Workflows

- [`Docker Benchmark`](.github/workflows/docker-cache-proofs.yml)
- [`Canary Benchmark`](.github/workflows/canary-dispatch.yml) runs the selected canary CLI and BuildKit image against the curated Docker cases in [`.canary/candidates.txt`](.canary/candidates.txt).

## Output

Each run uploads machine-readable JSON and Markdown summaries using the same artifact shape as the other BoringCache benchmark repositories.
