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

The CLI canary normalizes the classic command onto its disposable managed
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

Use a new suffix so no older proof can seed the series. The Docker build-family
support is currently on the CLI canary, so the proof must pin that exact channel
until the signed release containing it is available.

```bash
for case_id in mediswarm-odelia mediswarm-stamp; do
  ./scripts/dispatch-proof-series.sh \
    --case "$case_id" \
    --ref mediswarm-classic-proof \
    --rolling-bootstrap-ref seed \
    --lane-filter buildkit \
    --cli-version vcli-canary-851ae8ac013f \
    --cache-scope-suffix mediswarm-rolling-1 \
    --warm-replay \
    --skip-fresh
done
```

## Result

Pending the isolated seed, five changed-commit builds, and unchanged final
replay for both image tags.

## Upstream boundary

This is a prospect proof, not yet an outbound integration patch. The current
signed CLI release does not contain classic-command normalization, and the
MediSwarm validation job runs on a long-lived privileged self-hosted runner.
An upstream proposal should wait for the signed CLI release and must make the
runner trust boundary explicit. The result that matters is the first rolling
ODELIA and STAMP build after pruning; the already-fast second ODELIA build is
not the acceptance metric.
