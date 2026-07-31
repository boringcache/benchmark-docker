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
Both cases build the same upstream Dockerfile and the same six consecutive
source trees, starting five commits before the issue-era tip. The sequence
includes Go changes, a docs-only change, a dependency/dashboard change, and a
workflow-only change; the Dockerfile remains byte-identical throughout. Every
context change invalidates the upstream `COPY . .`, so its expensive Go build
step executes again. The `-go` case differs only by enabling
`go:{CACHE_SCOPE}-go` through `boringcache docker --tool-cache`, isolating Go
build-cache reuse across the full rolling series.

The proof uses fresh GitHub-hosted `ubuntu-24.04` runners and isolated cache
scopes. A cold rolling bootstrap seeds each scope, then each lane advances
through the same five parent-child commits in order. The GHA and BoringCache
Docker-only controls run together; the second case adds only the Go tool cache.
All 15 rolling samples below were valid.

Each result is `measured build / make build-binary / cache export`, in seconds.
The control-run links contain both GHA and BoringCache Docker-only jobs.

| Transition | Upstream change | GHA | BoringCache Docker | BoringCache Docker + Go |
|---|---|---:|---:|---:|
| [`9565ae6c`](https://github.com/grafana/cloudcost-exporter/commit/9565ae6cbef0759e53e1e54a5efec36219eabeaf) | RDS Go code | [168 / 119.6 / 19.3](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625777642) | [144 / 113.5 / 1.0](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625777642) | [66 / 24.8 / 0.8](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628444858) |
| [`b5564877`](https://github.com/grafana/cloudcost-exporter/commit/b55648776f0d9eb8f245a7fdbd6121a59446e174) | Exporter and AWS Go code, tests, docs | [149 / 114.4 / 12.4](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625991786) | [134 / 91.8 / 1.4](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625991786) | [65 / 24.5 / 0.8](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628565861) |
| [`0304705a`](https://github.com/grafana/cloudcost-exporter/commit/0304705af4cbc54dc4a6a9cadbca9ab59f8c690b) | Docs only | [174 / 115.8 / 28.5](https://github.com/boringcache/docker-cache-proofs/actions/runs/30626178332) | [144 / 115.7 / 0.9](https://github.com/boringcache/docker-cache-proofs/actions/runs/30626178332) | [73 / 21.5 / 1.0](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628691013) |
| [`26977e7e`](https://github.com/grafana/cloudcost-exporter/commit/26977e7e0066177ef80cce649b5071745f566a86) | Go dependencies, collectors, dashboards | [182 / 116.4 / 45.9](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627448143) | [140 / 93.5 / 1.3](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627448143) | [62 / 25.1 / 0.7](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628817577) |
| [`580113c9`](https://github.com/grafana/cloudcost-exporter/commit/580113c9610da388dda767eaa0acbf8d0cc2fbeb) | Workflow only | [173 / 118.4 / 22.5](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627697134) | [142 / 112.0 / 0.9](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627697134) | [62 / 25.6 / 1.1](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628942929) |

| Lane | Median measured build | Median compile | Median export | Median job wall time |
|---|---:|---:|---:|---:|
| [Grafana historical run](https://github.com/grafana/cloudcost-exporter/actions/runs/27209558109/job/80335379406) | 199s | 116.8s | 40.0s | 3m 34s |
| GHA rolling control | 173s | 116.4s | 22.5s | 3m 19s |
| BoringCache Docker | 142s | 112.0s | 1.0s | 2m 35s |
| BoringCache Docker + Go | 65s | 24.8s | 0.8s | 1m 22s |

The historical Grafana row is one issue-era run rather than a median; its
199-second Docker action contains the reported 116.8-second compile and
40-second GHA export. Its trigger commit has the same source tree as the last
rolling commit above.

Across the five contemporary rolling transitions, BoringCache Docker-only cut
median export time by 95.6% versus GHA, but its 112-second median compile
remained effectively cold. Adding the Go tool cache cut median measured build
time another 54.2% versus Docker-only (62.4% versus GHA), cut median compile
time by 77.9% versus Docker-only, and cut median job wall time to 1m 22s.

## Workflows

- [`Docker Benchmark`](.github/workflows/docker-cache-proofs.yml)
- [`Canary Benchmark`](.github/workflows/canary-dispatch.yml) runs the selected canary CLI and BuildKit image against the curated Docker cases in [`.canary/candidates.txt`](.canary/candidates.txt).

## Output

Each run uploads machine-readable JSON and Markdown summaries using the same artifact shape as the other BoringCache benchmark repositories.
