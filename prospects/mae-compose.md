# MAE Docker Compose cache proof

[MAE issue #490](https://github.com/cuttlefisch/mae/issues/490) reports that
three Docker-based CI jobs rebuild from scratch on separate GitHub-hosted
runners. The measured jobs took 11m34s, 11m37s, and 12m47s: about 36 aggregate
Docker minutes per CI run.

MAE already has a dependency-only Rust build layer in its Dockerfile. The layer
can help later builds only when BuildKit can restore it on the next runner.

## What this proof tests

The proof keeps MAE's three Compose definitions and the build-owning lifecycle
commands from the reported upstream run:

- `docker compose run --rm --build smoke`
- `docker compose -f docker-compose.collab-test.yml up --build --wait`
- `docker compose -f docker-compose.headless-e2e.yml up --build --wait`

Each command runs in its own benchmark job, matching the three independent
upstream runners. The containers case stops after `smoke`: in the cited MAE
run, that step consumed 11m24s and the following `new-user` build completed in
the same recorded second because it reused the first build's local runner
state.

The rolling series seeds `2d97d3bcd95a`, four first-parent commits behind the
current pin, then builds `62f89ce78a4a`, `8e71f85c30f2`, `631a702e2ec8`, and
`e46d77e183ac` in order. The issue-era `3b5d29b75cfa` source remains a separate
exact control for the published upstream timings.

The tool-cache follow-up wraps the real Compose command directly:

```bash
boringcache docker \
  --workspace boringcache/docker-cache-proof \
  --tag <scope> \
  --cache-mode max \
  --tool-cache sccache:<scope>-sccache \
  --no-platform \
  --no-git \
  --fail-on-cache-error \
  -- docker compose --file <compose-file> <run-or-up-command>
```

The CLI resolves the Compose project and supplies a temporary per-service cache
override. Compose still owns the build, container lifecycle, health checks, and
local images; the proof does not translate MAE's project into a maintained Bake
file or add cache settings to its source.

The follow-up copies MAE's pinned upstream Dockerfile into a benchmark overlay
and changes only the Rust cache plumbing: it installs pinned `sccache` 0.14.0,
receives the Docker tool-cache environment through a BuildKit secret, sets
`RUSTC_WRAPPER=sccache`, and puts `/mae/target` on a named BuildKit cache mount.
This is the Docker-native path. `boringcache cargo` cannot wrap these Cargo
processes because they execute inside Docker build steps.

The containers series also enables BoringCache's BuildKit cache-mount offload.
The collab and headless Compose files expand one Docker build into five and
three build targets respectively. The current canary resolved those targets
and applied sccache, but emitted no cache-mount lifecycle plan, so their clean
series measures Docker layer cache plus sccache without claiming target-mount
offload.

The two `up --wait` cases preserve MAE's Makefile success contract: Compose may
return nonzero when the one-shot `verifier` service stops, so the harness accepts
that result only when the verifier's recorded exit code is zero. Other lifecycle
failures remain failures and include scoped Compose status and logs in the proof
artifact.

## Result

The original proof used BoringCache's Docker layer cache only. It was not held
back by general service or CLI instability; it cached at the wrong level for
MAE's recent changes.

On the exact issue revision, the three upstream Docker steps totaled 35m28s.
The fresh BoringCache controls totaled 37m33s: 2m05s slower (5.9%). Cold cache
setup did not improve the build.

The four changed-source waves averaged 37m38s. Every selected commit changed
`Cargo.lock` or a Cargo manifest copied into the dependency layer, so each wave
rebuilt the expensive Rust dependencies. BuildKit still restored 13–33 steps
per wave, while cache import averaged 0.3s and export averaged 0.7s, but that
partial reuse did not materially shorten the aggregate Docker time.

The unchanged-source replay shows that the Compose path itself works. Repeating
the final revision reduced the aggregate measured command from 37m46s to 2m54s:
34m52s less (92.3%). The three replays restored 112 BuildKit steps and still ran
MAE's real smoke, collaboration, and headless verifier lifecycles.

The Docker tool-cache follow-up changes the rolling result. Its fresh seed took
39m08s versus 36m52s for the layer-only seed, a 2m16s (6.1%) cold-cache cost.
Across the next four commits, however, the three jobs fell from 9,033 aggregate
seconds with layer cache alone to 3,557 seconds with the Docker tool-cache path:
5,476 seconds saved, or 60.6%.

The two multi-build Compose jobs show why. On every rolling wave, sccache reused
at least 744 of 767 Rust compile requests (97.0%); the layer-only proof had to
rebuild the dependency layer. The single-build containers job combined sccache
with the persistent target mount and averaged 227s instead of 747s (69.7%
less). Its target archive hydrated successfully on every rolling commit and
grew from 797 MB after the seed to 1.06 GB after rolling 4.

## Layer-only runs

Each linked value is the measured Compose command, not the complete workflow
job. `Cached` is the sum of cached BuildKit steps across the three independent
jobs.

| Source | Containers | Collab E2E | Headless E2E | Aggregate | Cached |
|---|---:|---:|---:|---:|---:|
| Upstream issue `3b5d29b75cfa` | [684s](https://github.com/cuttlefisch/mae/actions/runs/30300856171/job/90093190973) | [687s](https://github.com/cuttlefisch/mae/actions/runs/30300856171/job/90093134731) | [757s](https://github.com/cuttlefisch/mae/actions/runs/30300856171/job/90093191038) | 2,128s | No persistent cache |
| BoringCache issue control | [733s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639151559) | [751s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641600692) | [769s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641674343) | 2,253s | Fresh |
| Seed `2d97d3bcd95a` | [651s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640098925) | [749s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642552402) | [812s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642655364) | 2,212s | 0 |
| Rolling 1 `62f89ce78a4a` | [753s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640937726) | [721s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643503820) | [796s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643671704) | 2,270s | 33 |
| Rolling 2 `8e71f85c30f2` | [745s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641929576) | [772s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644410268) | [818s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644691930) | 2,335s | 13 |
| Rolling 3 `631a702e2ec8` | [742s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642885205) | [613s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30645396296) | [807s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30645759096) | 2,162s | 15 |
| Rolling 4 `e46d77e183ac` | [746s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643860582) | [726s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30646189034) | [794s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30646755726) | 2,266s | 13 |
| Exact warm replay | [18s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644808280) | [73s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30647094645) | [83s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30647730389) | 174s | 112 |

## Docker tool-cache follow-up

`Rust reuse` is the aggregate Rust sccache hit count across the three jobs. The
containers job also has BoringCache target-mount offload; collab and headless do
not, for the multi-target reason above.

| Source | Containers | Collab E2E | Headless E2E | Aggregate | Rust reuse |
|---|---:|---:|---:|---:|---:|
| Seed `2d97d3bcd95a` | [781s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30661479797) | [757s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30661479715) | [810s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30661479821) | 2,348s | Fresh |
| Rolling 1 `62f89ce78a4a` | [148s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30662341444) | [238s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30662340042) | [299s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30662373823) | 685s | 1,555 / 1,557 (99.9%) |
| Rolling 2 `8e71f85c30f2` | [266s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30662549305) | [364s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30662642092) | [374s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30662737669) | 1,004s | 1,488 / 1,557 (95.6%) |
| Rolling 3 `631a702e2ec8` | [233s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30662878221) | [304s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30663066641) | [368s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30663174056) | 905s | 1,530 / 1,557 (98.3%) |
| Rolling 4 `e46d77e183ac` | [259s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30663186983) | [327s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30663453206) | [377s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30663666957) | 963s | 1,488 / 1,557 (95.6%) |
| Rolling average | 227s | 308s | 355s | 889s | 97.3% |
| Exact warm replay | [21s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30663970136) | [47s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30663874185) | [93s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30664145015) | 161s | Build steps cached |

## Evidence

The upstream control is [MAE run 30300856171](https://github.com/cuttlefisch/mae/actions/runs/30300856171).
All BoringCache evidence is on the
[`mae-compose-proof` branch](https://github.com/boringcache/docker-cache-proofs/actions?query=branch%3Amae-compose-proof),
and every run above publishes its benchmark JSON and BuildKit log as workflow
artifacts.

Both proof phases pin CLI `vcli-canary-851ae8ac013f` and BuildKit
`v0.30.0-bc.14@sha256:9b44a5426d7e32db41584c8d7d9f5251b0ad8348427e15849b541418030e7dab`.
The tool-cache phase additionally pins sccache 0.14.0. The case files pin every
source revision and use separate cache scopes for the three Compose projects.
Every clean-series sccache report recorded zero cache timeouts, read errors,
write errors, and cache errors. BoringCache's production telemetry independently
records OCI and sccache reads for the linked runs.

During setup, the headless service hit its own watchdog health timeout twice
before its verifier could start. The cache operation completed normally; the
exact-ref retry and all six chronological headless runs passed. Those setup
failures are [run 30639151606](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639151606)
and [run 30640450349](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640450349).

## What this would mean for MAE

MAE is a credible Docker tool-cache prospect. The follow-up directly answers
the manifest-invalidation problem that defeated the layer-only proof, preserves
the upstream Compose lifecycle, and shows repeatable 55.9% to 69.7% per-job
rolling savings across four real commits.

The honest recommendation is narrower than “turn on every cache.” MAE would
need the small Dockerfile integration in this proof and should use
`boringcache docker --tool-cache sccache:<scope>` for all three jobs. Target-mount
offload is also proven for the single-build containers path, but should not yet
be promised for the unchanged collab and headless files: the canary still needs
to deduplicate or otherwise plan their repeated Compose build targets.
