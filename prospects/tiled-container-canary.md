# Bluesky Tiled multi-platform container proof

[Tiled issue #1454](https://github.com/bluesky/tiled/issues/1454) reported
slow container builds. The merged
[PR #1455](https://github.com/bluesky/tiled/pull/1455) improved Dockerfile
ordering, but two recent successful runs still spent 10–13 minutes in the
container job. Much of that time was remote cache preparation and upload.

This proof replays the expensive first `linux/amd64,linux/arm64` build on fresh
GitHub-hosted runners. It intentionally leaves out Tiled's later same-job
single-platform test build so the rolling result answers one question: how
quickly can the first image build start from a reusable cross-run cache?

## Current upstream evidence

| Upstream run | First multi-platform build | Later single-platform build | Container job | Cache export |
|---|---:|---:|---:|---:|
| [July 31 run](https://github.com/bluesky/tiled/actions/runs/30610469144/job/91091895475) | 10m22s | 1m48s | 12m56s | 295.2s + 43.2s |
| [July 29 run](https://github.com/bluesky/tiled/actions/runs/30519607891/job/90796886436) | 9m38s | 1m39s | 12m00s | 273.3s + 30.0s |

The later build is fast partly because it follows a related build in the same
job. It is not the cross-run metric this proof is designed to improve.

## The shared GHA scope matters

Both upstream builds use bare `type=gha` entries. BuildKit therefore gives both
the default `scope=buildkit`. Docker's
[GHA cache backend documentation](https://docs.docker.com/build/cache/backends/gha/#scope)
states that each cache export to the same location overwrites the previous one.
In Tiled's job, the later single-platform cache export replaces the earlier
multi-platform export. The next run's first build can still find some cache,
but it does not receive an independently preserved cache for its exact output;
both recent logs also contain a missing cache blob during import.

That is a workflow-scoping problem as well as a cache-transport cost. The
controlled proof avoids it by running only the first multi-platform build in
each isolated rolling scope. It does not claim that changing the backend can
repair bad cache keys or make two incompatible exports coexist under one tag.

## Controlled rolling series

The pinned series starts before the Dockerfile ordering fix and ends at current
`main`:

| Case ref | Upstream revision | Purpose |
|---|---|---|
| `seed` | [`1853c2a1`](https://github.com/bluesky/tiled/commit/1853c2a1c58792815ef331af0c5d9cc9191773da) | Cold bootstrap for an isolated scope |
| `rolling1` | [`1d2b1c53`](https://github.com/bluesky/tiled/commit/1d2b1c53205cb807628d5f96751189f4cd942463) | Pre-fix source transition |
| `rolling2` | [`d642062a`](https://github.com/bluesky/tiled/commit/d642062ac966fed9bff2549df50408568aedbdbe) | Pre-fix source transition |
| `rolling3` | [`d7b26041`](https://github.com/bluesky/tiled/commit/d7b2604156a80b544ed9b6c7b654d88af9b0971d) | Merged Dockerfile ordering fix |
| `rolling4` | [`14a4368c`](https://github.com/bluesky/tiled/commit/14a4368c35e24172d008e8b0486a15d804010b9a) | First post-fix backend comparison |

The first two transitions show what the backend can reuse with the old layer
keys; they should not be averaged together with the post-fix result. The
`rolling3` transition changes the Dockerfile itself. `rolling4` is the cleanest
measure of remote cache behavior after the upstream fix has already landed.

Run the ordered pair with an isolated scope and no image output:

```sh
./scripts/dispatch-proof-series.sh \
  --case tiled-container-canary \
  --rolling-bootstrap-ref seed \
  --lane-filter all \
  --build-output none \
  --cache-scope-suffix tiled-rolling-2 \
  --skip-fresh
```

The earlier `tiled-rolling-1` attempt was cancelled after a duplicate manual
dispatch made the helper follow the wrong seed run. It is excluded from the
result. The workflow and helper now attach a unique dispatch token to every run
name, and the controlled series below uses the fresh `tiled-rolling-2` scope.

The two lanes use the same source, upstream `Containerfile`, QEMU setup,
`TILED_VERSION` build argument, two target platforms, provenance setting, and
GitHub-hosted runner class. GitHub Actions Cache uses `type=gha,mode=max`;
BoringCache uses its CLI-managed native BuildKit cache backend. Neither lane
pushes an image.

## Result

The post-fix backend comparison is decisive. On `rolling4`, after the
Dockerfile ordering fix had already landed, the complete measured phase took
98 seconds with BoringCache versus 258 seconds with GHA, a 62% reduction. The
underlying build commands were 98 versus 250 seconds. GHA spent 59.3 seconds
preparing its cache export; BoringCache's finalizer took 0.1 seconds.

An unchanged replay of the same revision took 7 seconds with BoringCache and
19 seconds with GHA (12 seconds for GHA's build command plus its builder
setup). Both backends are fast when every input is hot; the important result is
the first post-fix build after a real source transition.

| Source | BoringCache measured phase | GHA measured phase | GHA cache preparation |
|---|---:|---:|---:|
| `1853c2a1` isolated cold seed | [372s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643182520) | [646s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643182520) | 235.7s |
| `1d2b1c53` pre-fix transition | [356s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644066394) | [662s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644066394) | 187.4s |
| `d642062a` pre-fix transition | [329s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644951880) | [827s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644951880) | 197.1s |
| `d7b26041` Dockerfile-fix transition | [358s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30646060165) | [910s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30646060165) | 209.3s |
| `14a4368c` post-fix transition | [98s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30647192034) | [258s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30647192034) | 59.3s |
| Unchanged `14a4368c` replay | [7s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30647624528) | [19s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30647624528) | 0.7s |

Each measured phase includes cache import/export and, for GHA, its per-job
builder setup. These are ordered transition samples, not repeated statistical
trials. The cancelled `tiled-rolling-1` run is excluded.

BoringCache served 111 of 112 cache objects on the post-fix transition.
Internal telemetry nevertheless flagged elevated object-storage first-byte
latency on both the Dockerfile-fix and post-fix runs. That is an operator issue
to investigate, but it did not create the win: the post-fix solve still spent
27 seconds in the ARM application dependency step, while the backend avoided
GHA's separate cache-preparation tail.

## Adoption boundary

The intended production lane is a trusted `main`, scheduled, or manual build.
BoringCache restore credentials should not be exposed to untrusted fork pull
requests or through `pull_request_target`. Fork builds can keep GitHub Actions
Cache or run cold. This proof evaluates cache behavior; it does not change that
secret boundary.
