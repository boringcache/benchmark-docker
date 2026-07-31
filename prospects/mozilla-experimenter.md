# Mozilla Experimenter Docker Bake cache proof

[Experimenter issue #16332](https://github.com/mozilla/experimenter/issues/16332)
reports that about 22 CI jobs rebuild the same Docker layers. Its
`setup-cached-build` action builds `megazords`, `schemas`, and `cirrus`, then
jobs build an Experimenter test, development, or deployment image. The issue
measured 2–3.6 minutes of repeated setup work per job.

The issue's proposed GitHub Actions Cache integration is not a one-line cache
change. The `docker-container` driver cannot consume the locally loaded
`experimenter:megazords` build context, so the proposal also adds a temporary
registry, pushes `megazords` to it, and rewrites downstream build contexts.

## What this proof tests

The proof pins the issue-era source and expresses one representative test-job
graph as four Bake targets:

- `megazords`
- `schemas`
- `cirrus`
- `experimenter-test`

Bake's `target:megazords` context connects the dependent images without a
temporary registry. BoringCache discovers the selected targets and gives each
one an isolated cache automatically:

```bash
boringcache docker \
  --workspace boringcache/docker-cache-proof \
  --tag <scope> \
  --cache-mode max \
  --no-platform \
  --no-git \
  --fail-on-cache-error \
  -- docker buildx bake \
    --file docker-bake.hcl \
    --progress=plain \
    --load \
    ci-test
```

## Result

The rolling result is mixed, and much closer than the unchanged-source result:

| Average across Rolling 2–4 | GitHub Actions Cache | BoringCache | Difference |
|---|---:|---:|---:|
| Measured phase | 3m25s | 3m21s | BoringCache 3s less (2%) |
| Bake command | 3m17s | 3m21s | GHA 5s less (2%) |
| Slowest target cache export | 7.0s | 2.1s | BoringCache 3.4x shorter |

GHA pays 7–10 seconds of builder setup outside the Bake command. BoringCache
has the shorter measured phase after including that setup, while GHA has the
slightly shorter Bake command. Rolling 2 was effectively tied, GHA won Rolling
3, and BoringCache won Rolling 4. This proof does not support presenting either
backend as the universal rolling-build winner for this graph.

The first build is different. GHA's `mode=max` export took 178.1 seconds on the
rolling bootstrap, versus a 0.3-second BoringCache finalizer. BoringCache sends
new bodies while the solve is running, so 0.3 seconds is the final export step,
not its total network work. That architectural difference accounts for almost
all of BoringCache's 2m55s command-time lead on the cold bootstrap.

## Evidence

`Measured phase` includes GHA's builder setup. `Bake command` is the wall time
of one `docker buildx bake`, including cache import, image output, and cache
export. Cache import and export are the slowest concurrent Bake target, not the
sum of all four targets.

| Source | Evidence | Cached steps (BC / GHA) | Measured phase (BC / GHA) | Bake command (BC / GHA) | Export (BC / GHA) |
|---|---|---:|---:|---:|---:|
| Isolated seed `1470cbd9ac2a` | [run 30638453145](https://github.com/boringcache/docker-cache-proofs/actions/runs/30638453145) | 0 / 0 | 308s / 462s | 308s / 455s | 0.4s / 157.1s |
| Exact warm replay | [run 30639064219](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639064219) | 79 / 84 | 101s / 107s | 101s / 97s | 1.1s / 2.1s |
| Rolling 1 bootstrap `14901f442a10` | [run 30639461805](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639461805) | 0 / 0 | 296s / 476s | 295s / 470s | 0.3s / 178.1s |
| Rolling 2 `9663c40fa517` | [run 30640108793](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640108793) | 79 / 79 | 152s / 150s | 152s / 143s | 1.1s / 4.8s |
| Rolling 3 `23484f476889` | [run 30640349046](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640349046) | 79 / 77 | 237s / 199s | 237s / 189s | 1.9s / 5.9s |
| Rolling 4 `1470cbd9ac2a` | [run 30640709753](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640709753) | 77 / 77 | 215s / 265s | 215s / 258s | 3.2s / 10.2s |

Every `--load` run checked that all four expected local image tags existed. The
logs also record their image digests. The warm replay therefore proves the
unchanged-source path without weakening the local-image requirement that makes
this prospect interesting.

### Why GHA was faster on Rolling 3

It was not a cache-hit or cache-export win. BoringCache served 192 of 193 cache
objects (99.5%), recorded only three new blobs totaling 3.28 MB, cached two
more reported BuildKit steps, and exported four seconds faster. There were no
cache errors or retries.

The 48-second Bake-command gap appears in two places:

| Rolling 3 work | GitHub Actions Cache | BoringCache | Gap |
|---|---:|---:|---:|
| `COPY . /experimenter/` | 2.2s | 12.7s | 10.5s |
| First image output start to final image output finish | 170.6s | 206.2s | 35.6s |

Those non-overlapping intervals explain about 46 of the 48 seconds. Individual
`exporting to docker image format` spans were 17.3–70.1 seconds for GHA and
64.1–85.3 seconds for BoringCache. They run concurrently, so they should not be
added together; the first-to-last output window above is the relevant wall
time.

BoringCache's session telemetry agrees with the trace. The cache was hot, but
the current read path fetched 2.11 GB of bodies from the `sjc1` storage origin
and classified the primary bottleneck as `cache_transport`. Storage body work
totaled 129 seconds across concurrent requests, including 1.08 GB and 100
seconds of aggregate range-rescue work. This is a real read-path warning for a
graph that must materialize four large images into a fresh runner's Docker
store.

GHA does not expose comparable lazy body-fetch telemetry, so this run cannot
prove that its backend was closer to the runner or intrinsically faster. It
only shows that its combined Actions-cache body delivery and local Docker
materialization path was faster in this sample. Fresh hosted-runner disk and
network variation may also contribute.

We checked the attribution with a diagnostic `output=none` replay of Rolling 3
against the same stable cache scopes after the series had advanced. Both Bake
commands took exactly 67 seconds and cached 79 steps. The measured phase was 67
seconds for BoringCache and 74 seconds for GHA because of GHA's seven-second
builder setup: [run 30641565751](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641565751).
Removing local image output therefore removes the reversal. This control is a
diagnostic, not a replacement for the prospect proof, because Experimenter's
later steps require those local images.

### Rolling inputs

The four snapshots follow issue-era first-parent history and each changes a
Docker input, rather than using workflow-only commits as artificial churn:

| Ref | Commit | Docker-input change |
|---|---|---|
| `rolling1` | `14901f442a10` | Feature manifests |
| `rolling2` | `9663c40fa517` | Removed Experimenter code |
| `rolling3` | `23484f476889` | Rollout templates |
| `rolling4` | `1470cbd9ac2a` | Nimbus DevTools code |

Both lanes used the same GitHub-hosted runner class, source, upstream
Dockerfiles, contexts, four-target Bake graph, `mode=max`, and mandatory image
checks. The proof pinned BoringCache CLI `vcli-canary-6636517dfa2d` and BuildKit
image
`ghcr.io/boringcache/buildkit@sha256:f56e172ee45223ba57dbf37cf11fbfb7880c5637ea83e55315d53a439bd187c6`.

The GHA storage number exposed by GitHub is repository-wide, while the
immediate BoringCache storage lookup did not return a comparable case-specific
value. This proof therefore makes no storage comparison.

## Run it again

Use a new suffix so an older run cannot seed the results:

```bash
./scripts/dispatch-proof-series.sh \
  --case mozilla-experimenter \
  --ref experimenter-bake-proof \
  --skip-fresh \
  --rolling-bootstrap-ref rolling1 \
  --lane-filter gha-buildkit \
  --cache-scope-suffix experimenter-bake-rerun-1 \
  --warm-replay \
  --cli-version vcli-canary-6636517dfa2d \
  --buildkit-image \
    ghcr.io/boringcache/buildkit@sha256:f56e172ee45223ba57dbf37cf11fbfb7880c5637ea83e55315d53a439bd187c6
```

## What this would mean for Experimenter

This is a design-partner integration, not a drop-in replacement. The proof
tests the exact Dockerfiles and image dependency, but adopting it would mean
making Bake the owner of the build graph and then fitting that graph into the
existing composite action, retry behavior, Make targets, and Compose-based test
lifecycle.

The expected UX improvement is narrower and concrete: one cached Bake command
can replace the per-image cache flags and the temporary registry workaround,
while preserving the local image tags that later job steps use.
