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

The measured rolling pair used fresh GitHub-hosted `ubuntu-24.04` runners and
isolated cache scopes. Both samples imported usable Docker cache, reused five
Docker steps, executed the same final `make build-binary` step, and exported
cache in 0.8 seconds.

| Lane | Measured build | `make build-binary` | GitHub job wall time |
|---|---:|---:|---:|
| [Docker only](https://github.com/boringcache/docker-cache-proofs/actions/runs/30624756311) | 143s | 115.1s | 2m 34s |
| [Docker + Go](https://github.com/boringcache/docker-cache-proofs/actions/runs/30624756242) | 63s | 23.7s | 1m 16s |

Adding the Go tool cache cut the measured build by 80 seconds (56%), the
re-executed compile step by 91.4 seconds (79%), and the complete job by 78
seconds (51%). The Docker-only lane's 115.1-second compile also closely
reproduces the upstream issue's reported 117-second cold Go compile.

## Workflows

- [`Docker Benchmark`](.github/workflows/docker-cache-proofs.yml)
- [`Canary Benchmark`](.github/workflows/canary-dispatch.yml) runs the selected canary CLI and BuildKit image against the curated Docker cases in [`.canary/candidates.txt`](.canary/candidates.txt).

## Output

Each run uploads machine-readable JSON and Markdown summaries using the same artifact shape as the other BoringCache benchmark repositories.
