# BIAR Spark-stack Docker cache proof

[BIAR issue #142](https://github.com/tazama-lf/biar/issues/142) reported that
three Spark-stack images took more than 20 minutes each without Docker layer
caching:

- `automation-orchestrator`
- `datalakehouse-api`
- `jupyterhub`

The images independently install Java 11, Spark 3.4.2, Hudi, and related data
dependencies. Spark 3.4.2 is no longer available from Apache's CDN, so cold
builds still fall back to the slower archive host.

## Upstream state

BIAR added per-image `type=gha,mode=min` caches through
[pull request #150](https://github.com/tazama-lf/biar/pull/150). The following
run added the required Buildx driver after the first cache-enabled attempt
failed:

| Image | Last uncached job | First successful cache-enabled job |
|---|---:|---:|
| `automation-orchestrator` | 17m42s | 5m21s |
| `datalakehouse-api` | 12m47s | 4m25s |
| `jupyterhub` | 22m46s | 9m26s |

The successful run imported GHA cache manifests but rebuilt the expensive
layers. Most of its apparent improvement came from a much faster response from
Apache's archive host. BIAR did not dispatch the unchanged second build needed
to demonstrate a warm GHA result.

`mode=min` is a deliberate compromise: BIAR's issue notes that GitHub's default
10 GB repository cache allowance may not hold three roughly 2.4 GB images with
full intermediate `mode=max` graphs.

## Prospect question

Can BoringCache preserve the full BuildKit cache for all three independent
images and make an unchanged rebuild predictable without sharing BIAR's default
repository-wide GHA cache allowance?

## What this proof tests

The three case manifests retain BIAR's original Dockerfiles, build contexts,
`linux/amd64` platform, and separate per-image cache identities.

The exact-replay check runs the current pinned source twice:

1. a cold rolling build that seeds a new BoringCache scope;
2. an unchanged replay that restores and republishes that scope.

The rolling check starts four context-changing commits back and advances
through four later commits. Each case follows its own linear ancestry so every
step changes files inside that image's Docker build context. The final commit
changes the Spark download instruction in all three Dockerfiles, deliberately
testing a layer-invalidating change after three ordinary source changes.

The build output is `none`. That isolates layer-cache import, execution, and
export from Docker Hub image-push time, so these results must not be presented
as an end-to-end replacement for BIAR's publish-job durations.

## Run it

Use a new suffix for every series so an older cache cannot seed the cold run.
This runs the cold seed plus four rolling commits for both BoringCache and the
GHA `mode=max` control:

```bash
for case_id in \
  biar-automation-orchestrator \
  biar-datalakehouse-api \
  biar-jupyterhub
do
  gh workflow run docker-cache-proofs.yml \
    -f case_id="$case_id" \
    -f ref_key=main \
    -f cache_lane=rolling \
    -f build_output=none \
    -f cache_scope_suffix=biar-rolling-rerun-1
done
```

The cases reclaim hosted-runner tool caches before building because the three
large image graphs can otherwise exhaust the runner disk.

## Results

Run on GitHub-hosted `ubuntu-latest` runners on July 31, 2026. All 27 proof
workflows passed: twelve exact-replay workflows and fifteen workflows across the
three five-commit rolling histories.

### Exact replay

The measured build includes BuildKit cache import, execution, and export. The
GHA control used a fresh per-image `mode=max` scope; its warm run reused the
same scope. BoringCache used an equally fresh per-image tag.

| Image | BoringCache cold -> warm | GHA `mode=max` cold -> warm | GHA cold export | BoringCache logical graph |
|---|---:|---:|---:|---:|
| `automation-orchestrator` | 111s -> 9s | 283s -> 4s | 172.1s | 1.27 GiB |
| `datalakehouse-api` | 232s -> 14s | 206s -> 4s | 123.1s | 1.00 GiB |
| `jupyterhub` | 219s -> 12s | 496s -> 2s | 328.5s | 2.25 GiB |

BoringCache reduced the unchanged builds by 91.9%, 94.0%, and 94.5%. GHA was
also excellent on an unchanged hot replay while its cache remained available.
The useful difference for this prospect is therefore not the best-case no-op
build; it is the cost and predictability of preserving full intermediate cache
graphs across normal source changes.

The exact BoringCache entries total 4.53 GiB of logical graph data before
content-addressed deduplication. That is below GitHub's default 10 GB
repository allowance, so this proof does **not** claim the three final graphs
alone exceed the allowance.

### Five-commit rolling proof

These are complete GitHub job durations. `seed` starts four context-changing
commits back, `r1` through `r3` are ordinary source changes, and `r4` changes
the Spark download instruction and invalidates the expensive downstream
layers.

| Image | Cache | Seed | r1 | r2 | r3 | r4 layer bust |
|---|---|---:|---:|---:|---:|---:|
| `automation-orchestrator` | BoringCache | 2m00s | 49s | 40s | 36s | 2m01s |
| | GHA `mode=max` | 3m10s | 1m08s | 1m47s | 49s | 4m08s |
| `datalakehouse-api` | BoringCache | 1m53s | 44s | 37s | 36s | 1m25s |
| | GHA `mode=max` | 2m28s | 1m22s | 47s | 58s | 3m22s |
| `jupyterhub` | BoringCache | 4m02s | 1m04s | 1m08s | 1m14s | 2m59s |
| | GHA `mode=max` | 8m11s | 1m27s | 2m02s | 2m10s | 5m45s |

Across all fifteen rolling commits:

| Metric | BoringCache | GHA `mode=max` | Difference |
|---|---:|---:|---:|
| Measured BuildKit build time | 1,051s | 1,985s | 47.1% lower |
| BuildKit cache export time | 39.0s | 849.1s | 95.4% lower (21.8x) |
| Summed GitHub job time | 21m48s | 39m34s | 44.9% lower |

The layer-busting `r4` exports make the mechanism visible. BoringCache spent
3.5s, 2.5s, and 12.0s exporting the updated graphs; GHA spent 130.9s, 98.5s,
and 188.4s. BoringCache's rolling imports were classified as usable and reused
on every post-seed commit. Production telemetry found no BoringCache service
or operator issue; the large jupyterhub reads did produce a runner-local disk
pressure watch.

GitHub's repository-wide cache meter ranged from 9.94 GiB to 13.01 GiB during
the rolling series and dropped between samples as caches were updated. That
meter includes other proof caches, and the three series ran concurrently, so
it cannot establish how many bytes belonged only to BIAR or prove which entry
was evicted. It does confirm that a full-cache proof operates at the default
allowance boundary. BoringCache keeps these image graphs outside that shared
GHA allowance and deduplicates identical blobs across cache entries.

### Evidence and limits

- Exact BoringCache cold/warm runs: automation
  [cold](https://github.com/boringcache/docker-cache-proofs/actions/runs/30638373847) /
  [warm](https://github.com/boringcache/docker-cache-proofs/actions/runs/30638574658),
  datalakehouse
  [cold](https://github.com/boringcache/docker-cache-proofs/actions/runs/30638373652) /
  [warm](https://github.com/boringcache/docker-cache-proofs/actions/runs/30638684464),
  jupyterhub
  [cold](https://github.com/boringcache/docker-cache-proofs/actions/runs/30638373692) /
  [warm](https://github.com/boringcache/docker-cache-proofs/actions/runs/30638684393).
- Exact GHA cold/warm controls: automation
  [cold](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639005407) /
  [warm](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639431870),
  datalakehouse
  [cold](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639005685) /
  [warm](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639359508),
  jupyterhub
  [cold](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639005541) /
  [warm](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639688828).
- Rolling sequences: automation
  [seed](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639759548) to
  [r4](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640422674),
  datalakehouse
  [seed](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639759523) to
  [r4](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640270848),
  jupyterhub
  [seed](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639759487) to
  [r4](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640950086).
- Each rolling workflow paired the same source commit and runner class, but the
  two jobs used different VMs and external downloads can vary. Fresh
  BoringCache tags prevent cache import; the shared content-addressed store can
  still avoid uploading blobs already present from earlier proofs, which is an
  intended product behavior rather than a virgin-storage benchmark.
- `output=none` deliberately excludes image export and registry push time. The
  result demonstrates BuildKit cache behavior, not BIAR's full publish-job
  duration.

## Prospect verdict

This is a strong BoringCache Docker prospect. BIAR's existing `mode=min` change
is a sensible immediate fix and should remain; BoringCache is most compelling
when BIAR wants full `mode=max`-equivalent rolling reuse for all three images
without paying repeated multi-minute GHA exports or making those histories
compete inside the repository-wide GHA cache allowance.
