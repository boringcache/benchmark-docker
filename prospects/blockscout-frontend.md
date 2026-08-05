# Blockscout frontend Docker cache proof

[Blockscout reported](https://github.com/blockscout/frontend/issues/3602) that
its first successful GHCR `mode=max` cache export took 150.8 seconds, or 31% of
a 7m57s job. Replacing the cache tag also left the old manifest untagged.

We ran Blockscout's Dockerfile through five consecutive commits to answer two
questions:

- How much time could BoringCache save on a normal rolling build?
- Could Blockscout stop managing cache tags and old manifests in GHCR?

## Result

Each rolling build reused the cache from the commit before it.

| Average across five rolling builds | GHCR | BoringCache | Difference |
|---|---:|---:|---:|
| Build time | 11m00s | 7m42s | 3m18s less (30%) |
| Cache export | 4m30s | 3.1s | 87x shorter |

Both sides reused a similar number of BuildKit steps. The difference came
mostly from the time spent writing the updated cache.

## Runs

`Build` is the wall time of one `docker buildx build`. It includes the cache
export shown in the next column.

| Source | Evidence | Cached steps (BC / GHCR) | Build (BC / GHCR) | Export (BC / GHCR) | GHCR retained | Versions (untagged) |
|---|---|---:|---:|---:|---:|---:|
| Bootstrap `8d6e447a60c4` | [run 30624162195](https://github.com/boringcache/docker-cache-proofs/actions/runs/30624162195) | 0 / 0 | 443s / 637s | 2.7s / 258.7s | 1.94 GiB | 1 (0) |
| Rolling 1 `c3b79a0787b2` | [run 30624838863](https://github.com/boringcache/docker-cache-proofs/actions/runs/30624838863) | 26 / 29 | 453s / 688s | 3.0s / 313.1s | 3.71 GiB | 2 (1) |
| Rolling 2 `a204400d1a46` | [run 30625573930](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625573930) | 26 / 28 | 465s / 646s | 3.2s / 256.2s | 5.47 GiB | 3 (2) |
| Rolling 3 `3e8f4939ab7b` | [run 30627441739](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627441739) | 21 / 21 | 468s / 632s | 3.5s / 246.9s | 7.35 GiB | 4 (3) |
| Rolling 4 `39bb7b3e6e5d` | [run 30628168268](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628168268) | 26 / 27 | 478s / 635s | 3.1s / 255.8s | 9.11 GiB | 5 (4) |
| Rolling 5 `da93fdec5b11` | [run 30628873391](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628873391) | 15 / 13 | 448s / 701s | 2.7s / 278.0s | 10.88 GiB | 6 (5) |
| Exact warm replay | [run 30629682491](https://github.com/boringcache/docker-cache-proofs/actions/runs/30629682491) | 55 / 55 | 15s / 13s | 1.0s / 6.0s | 10.88 GiB | 7 (6) |

The five rolling builds averaged 660.4 seconds with GHCR and 462.4 seconds
with BoringCache. Cache export averaged 270.0 seconds with GHCR and 3.1 seconds
with BoringCache.

### Fully warm replay

We ran the final commit again without changing the source. Both builds cached
all 55 BuildKit steps. Cache import and export took 10.2 seconds with GHCR and
1.3 seconds with BoringCache. The complete jobs took 43 and 30 seconds.

The `buildx` command itself took 13 seconds with GHCR and 15 seconds with
BoringCache. The warm result shows less cache-transfer and job time, not faster
application work.

### Storage

After the warm replay, GHCR held 10.88 GiB across seven package versions. Six
versions were untagged, while the active cache graph was 1.93 GiB.

BoringCache had one current rolling tag pointing to a 1.81 GiB, 60-blob cache
graph. Older graphs no longer held that tag.

GHCR and BoringCache account for storage differently, so these figures should
not be used as a direct billing comparison. What the runs show is the GHCR
growth caused by old package versions and the untagged-manifest cleanup that
comes with it.

## What we tested

Both sides used the same GitHub-hosted runner class, source commit, Dockerfile,
build arguments, `linux/amd64` platform, BuildKit image, and `output=none`.

- GHCR used Blockscout's `mode=max`, OCI media type, image manifest settings,
  and one stable rolling tag.
- BoringCache used its normal CLI-managed BuildKit path and one stable rolling
  cache scope.

We left out Blockscout's `ignore-error=true` setting so the benchmark would
fail if a cache export failed.

The commits follow first-parent order on Blockscout's `main` branch:

| Ref | Commit | Change |
|---|---|---|
| `seed` | `8d6e447a60c4` | Exclude agent worktrees from lint and test runners |
| `rolling1` | `c3b79a0787b2` | Prometheus registry fix |
| `rolling2` | `a204400d1a46` | Shared agent rules reorganization |
| `rolling3` | `3e8f4939ab7b` | Merge the corepack retry and GHCR cache write-back change |
| `rolling4` | `39bb7b3e6e5d` | Worktree dependency and pruning hooks |
| `rolling5` | `da93fdec5b11` | `dotenv-cli` and lockfile update |

## Run it again

Use a new cache scope suffix each time so an older run cannot seed the results:

```bash
gh workflow run docker-cache-proofs.yml \
  -f case_id=blockscout-frontend \
  -f ref_key=main \
  -f cache_lane=rolling \
  -f build_output=none \
  -f cache_scope_suffix=blockscout-rerun-1
```

Dispatch each later pinned ref with the same scope suffix to extend the rolling
series. BoringCache records the product run; this repository does not duplicate
its receipt or cache-internal assertions.

## What this means for Blockscout

Blockscout can replace the workflow's `type=registry` cache import and export
with BoringCache's managed BuildKit path. The Dockerfile, layers, build
arguments, platform, and image output do not need to change.

In these five rolling builds, that saved an average of 3m18s per build and
removed the need to publish and clean up GHCR cache-package tags.
