# MediSwarm classic Docker cache proof

[MediSwarm issue #396](https://github.com/KatherLab/MediSwarm/issues/396)
identified an uncached 5.2 GB ODELIA image build in PR validation. Pull request
[#401](https://github.com/KatherLab/MediSwarm/pull/401) stopped passing
`--no-cache` to that build and enabled pip's download cache, but it did not add
a cache that survives the workflow's local builder cleanup.

The workflow still removes its ODELIA and STAMP images and runs
`docker builder prune -af` before building. The first ODELIA build therefore
starts without reusable Docker layers. Only the second ODELIA build in the same
job benefits from the local cache created by the first one.

## Upstream evidence

| Run | First ODELIA build | Second ODELIA build | STAMP build |
|---|---:|---:|---:|
| [July 7](https://github.com/KatherLab/MediSwarm/actions/runs/28854804461) | 2m27s | 46s | 2m26s |
| [July 30](https://github.com/KatherLab/MediSwarm/actions/runs/30531974555) | 2m58s | 49s | 1m58s |

The July 30 Docker logs make the boundary explicit: the first ODELIA solve
executed every dependency layer, while the second reported cache hits for all
of them. That is useful intra-job reuse, not cross-run caching.

## What this proof tests

The proof gives ODELIA and STAMP independent BoringCache tags and preserves the
upstream build shape:

- classic `docker build`, not an upstream workflow rewrite to a cache registry;
- the pinned ODELIA and STAMP Dockerfiles;
- the clean archived source tree, NVFlare submodule, version substitutions,
  and ODELIA model-weight inputs prepared by the upstream scripts; and
- an explicit `docker builder prune -af` before each measured build.

The recorded CLI canary normalized the classic command onto its disposable managed
BuildKit builder and preserves the classic local-image output. The cache lives
remotely under the per-image tag, so deleting the local builder does not delete
the next run's reusable layers.

The rolling series starts five first-parent commits behind current main and
advances one commit at a time. Both Dockerfiles are byte-identical across the
series, while MediSwarm's generated template embeds each commit ID and the
final application `COPY` changes with the source. This tests the ordinary case:
stable dependency layers should hit while the real commit-dependent tail
rebuilds.

## Run it

Use a new suffix so no older proof can seed the series. The command below
reproduces the recorded cohort with its exact canary. Current product reruns can
omit `--cli-version` to select the released v1.16.3 CLI.

```bash
for case_id in mediswarm-odelia mediswarm-stamp; do
  ./scripts/dispatch-proof-series.sh \
    --case "$case_id" \
    --ref mediswarm-classic-proof \
    --rolling-bootstrap-ref seed \
    --lane-filter buildkit \
    --build-output load \
    --cli-version vcli-canary-851ae8ac013f \
    --cache-scope-suffix mediswarm-load-1 \
    --warm-replay \
    --skip-fresh
done
```

## Result

The remote tags survived every local builder prune, but the complete
classic-build result is mixed. ODELIA's five changed revisions had a
271-second median versus a 385-second cold seed, a 30% reduction, but one
workflow-only transition took 494 seconds. STAMP's changed-revision median was
222 seconds versus 238 seconds cold, only a 7% reduction. The unchanged final
replays took 179 and 129 seconds respectively.

| Source | ODELIA classic build + load | STAMP classic build + load |
|---|---:|---:|
| [`42112a44`](https://github.com/KatherLab/MediSwarm/commit/42112a44979aacad525e5a26670755c3feba629a) cold seed | [385s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641893227) | [238s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641609224) |
| [`59423f44`](https://github.com/KatherLab/MediSwarm/commit/59423f44c53a6203a8e91057e7cf1ddbcd72e63e) | [252s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642484995) | [250s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642028409) |
| [`4c655a32`](https://github.com/KatherLab/MediSwarm/commit/4c655a328de036453247d2c4e4ba8a0e9bf989d9) | [494s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642928679) | [203s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642406320) |
| [`ccc78a8b`](https://github.com/KatherLab/MediSwarm/commit/ccc78a8b5ea2b99b83815be16aa5b39da247c67d) | [262s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643666591) | [222s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642779788) |
| [`9ac2ca56`](https://github.com/KatherLab/MediSwarm/commit/9ac2ca56d9fe1a783270a30ad81d36719bf1c320) | [271s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644109735) | [197s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643147934) |
| [`b46973a0`](https://github.com/KatherLab/MediSwarm/commit/b46973a036b7ffec6b94bdbc349118f64adc9dde) | [288s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644557902) | [237s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643457856) |
| Unchanged `b46973a0` replay | [179s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30645002326) | [129s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643822548) |

The replay telemetry explains the floor. ODELIA served 44 of 45 cache objects,
yet spent 164 seconds exporting the 5.2 GB result into the local Docker image
store. STAMP hit every cache object and still spent 121 seconds on the same
local-image export phase. BoringCache's final cache publication itself stayed
under one second in both runs.

These are ordered transition samples on GitHub-hosted runners, not repeated
statistical trials or direct subtractions from MediSwarm's privileged
self-hosted-runner timings. The proof establishes cross-run reuse after
pruning, but the mandatory `docker build` local-image boundary prevents a
consistent first-build win. MediSwarm should be downgraded from a top prospect
unless a design-partner test can reduce or avoid that materialization cost.

## Upstream boundary

This is a prospect proof, not yet an outbound integration patch. The current
signed CLI release does not contain classic-command normalization, and the
MediSwarm validation job runs on a long-lived privileged self-hosted runner.
An upstream proposal should wait for the signed CLI release and must make the
runner trust boundary explicit. The result that matters is the first rolling
ODELIA and STAMP build after pruning; the already-fast second ODELIA build is
not the acceptance metric.
