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
  ./scripts/dispatch-proof-series.sh \
    --case "$case_id" \
    --ref main \
    --rolling-bootstrap-ref seed \
    --lane-filter all \
    --cache-scope-suffix biar-rolling-rerun-1 \
    --skip-fresh
done
```

The cases reclaim hosted-runner tool caches before building because the three
large image graphs can otherwise exhaust the runner disk.

## Results

Pending the controlled cold and unchanged-replay series.
