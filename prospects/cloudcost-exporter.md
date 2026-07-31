# cloudcost-exporter Docker and Go cache proof

[cloudcost-exporter issue #1029](https://github.com/grafana/cloudcost-exporter/issues/1029)
describes feature-branch Docker builds taking about 3.5 minutes per architecture.
One issue-era `linux/amd64` job spent 116.8 seconds compiling Go and 40 seconds
exporting its BuildKit cache to GitHub Actions Cache.

We replayed five consecutive parent-child updates from the same source history
on fresh GitHub-hosted runners. The proof separates two variables: first replace
GitHub Actions Cache with BoringCache's Docker cache, then add BoringCache's Go
tool cache while keeping the Docker build unchanged.

## Result

| Median across five rolling transitions | GitHub Actions Cache | BoringCache Docker | BoringCache Docker + Go |
|---|---:|---:|---:|
| Measured build | 2m53s | 2m22s | 1m05s |
| `make build-binary` | 116.4s | 112.0s | 24.8s |
| Cache export | 22.5s | 1.0s | 0.8s |
| GitHub job wall time | 3m19s | 2m35s | 1m22s |

BoringCache Docker + Go was faster than both controls in all five rolling
transitions. It cut the median measured build by 62% and the median complete
job by 59% versus GitHub Actions Cache. The two-variable control shows where
the gains came from: BoringCache Docker cut median export by 96%, while the Go
tool cache cut the remaining median compile by 78%.

`Measured build` is one `docker buildx build`, including cache export. Job wall
time also includes checkout, setup, artifact reporting, and post-job cleanup.

## Rolling series

Each result is `measured build / make build-binary / cache export`, in seconds.
The control-run links contain both the GitHub Actions Cache and BoringCache
Docker jobs.

| Source | Upstream change | GitHub Actions Cache | BoringCache Docker | BoringCache Docker + Go |
|---|---|---:|---:|---:|
| [`9565ae6c`](https://github.com/grafana/cloudcost-exporter/commit/9565ae6cbef0759e53e1e54a5efec36219eabeaf) | RDS Go code | [168 / 119.6 / 19.3](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625777642) | [144 / 113.5 / 1.0](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625777642) | [66 / 24.8 / 0.8](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628444858) |
| [`b5564877`](https://github.com/grafana/cloudcost-exporter/commit/b55648776f0d9eb8f245a7fdbd6121a59446e174) | Exporter and AWS Go code, tests, docs | [149 / 114.4 / 12.4](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625991786) | [134 / 91.8 / 1.4](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625991786) | [65 / 24.5 / 0.8](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628565861) |
| [`0304705a`](https://github.com/grafana/cloudcost-exporter/commit/0304705af4cbc54dc4a6a9cadbca9ab59f8c690b) | Docs only | [174 / 115.8 / 28.5](https://github.com/boringcache/docker-cache-proofs/actions/runs/30626178332) | [144 / 115.7 / 0.9](https://github.com/boringcache/docker-cache-proofs/actions/runs/30626178332) | [73 / 21.5 / 1.0](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628691013) |
| [`26977e7e`](https://github.com/grafana/cloudcost-exporter/commit/26977e7e0066177ef80cce649b5071745f566a86) | Go dependencies, collectors, dashboards | [182 / 116.4 / 45.9](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627448143) | [140 / 93.5 / 1.3](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627448143) | [62 / 25.1 / 0.7](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628817577) |
| [`580113c9`](https://github.com/grafana/cloudcost-exporter/commit/580113c9610da388dda767eaa0acbf8d0cc2fbeb) | Workflow only | [173 / 118.4 / 22.5](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627697134) | [142 / 112.0 / 0.9](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627697134) | [62 / 25.6 / 1.1](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628942929) |

## Historical reference

The issue's
[3m34s `linux/amd64` job](https://github.com/grafana/cloudcost-exporter/actions/runs/27209558109/job/80335379406)
used the same source tree as the final rolling transition. Its 199-second Docker
action contained the reported 116.8-second compile and 40-second GitHub Actions
Cache export. It is a single historical reference rather than part of the
five-run contemporary medians above.

## What we tested

All three lanes used the same GitHub-hosted `ubuntu-24.04` runner class, source
revision, upstream Dockerfile, build context, `linux/amd64` platform, and
`output=none`.

- A cold bootstrap seeded each isolated rolling cache scope before the five
  measured source transitions.
- GitHub Actions Cache and BoringCache Docker ran together as the first-variable
  control.
- GitHub Actions Cache used BuildKit's `type=gha,mode=max` backend.
- BoringCache Docker used its CLI-managed BuildKit backend.
- BoringCache Docker + Go changed only the case identity, image name, and
  `go:{CACHE_SCOPE}-go` tool-cache setting.
- The Dockerfile remained byte-identical across all six source trees.
- No Dockerfile change, registry push, or image output was used.
- All 15 rolling samples were valid.

The pinned cases are
[`cloudcost-exporter-amd64.json`](../cases/cloudcost-exporter-amd64.json) and
[`cloudcost-exporter-amd64-go.json`](../cases/cloudcost-exporter-amd64-go.json).
All runs are public on the
[`cloudcost-exporter-proof` branch](https://github.com/boringcache/docker-cache-proofs/actions?query=branch%3Acloudcost-exporter-proof).

## What this means for cloudcost-exporter

The upstream `COPY . .` makes the final Go build step execute again whenever
the build context changes. BoringCache's Docker cache removes nearly all of the
remote cache-export cost, and its Go tool cache preserves useful compiler work
when that Docker step must re-execute on a fresh runner.

The project can keep its Dockerfile, build arguments, and GitHub-hosted runner.
The workflow opts into the BoringCache Docker and Go cache path without adding
registry cache tags to manage.
