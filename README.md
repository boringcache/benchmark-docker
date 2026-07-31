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

BoringCache has one Docker cache product path in these proofs. The CLI owns the
builder and emits the native `type=boringcache` cache configuration; registry
cache and alternate-backend benchmark lanes have been retired.

## Controlled Docker + Go Proof

The `cloudcost-exporter-amd64` and `cloudcost-exporter-amd64-go` cases form a
paired proof for [Grafana Cloud Cost Exporter issue #1029](https://github.com/grafana/cloudcost-exporter/issues/1029).
Both cases build the same upstream Dockerfile and the same two source trees.
The rolling commit changes only `.github/workflows/release-on-pr-merge.yml`, but
the upstream `COPY . .` still invalidates its expensive Go build step. The
`-go` case differs only by enabling `go:{CACHE_SCOPE}-go` through
`boringcache docker --tool-cache`, so the comparison isolates Go build-cache
reuse when Docker must execute that step again.

## Workflows

- [`Docker Benchmark`](.github/workflows/docker-cache-proofs.yml)
- [`Canary Benchmark`](.github/workflows/canary-dispatch.yml) runs the selected canary CLI and BuildKit image against the curated Docker cases in [`.canary/candidates.txt`](.canary/candidates.txt).

## Output

Each run uploads machine-readable JSON and Markdown summaries using the same artifact shape as the other BoringCache benchmark repositories.
