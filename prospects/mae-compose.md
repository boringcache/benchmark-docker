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

BoringCache wraps the real Compose command directly:

```bash
boringcache docker \
  --workspace boringcache/docker-cache-proof \
  --tag <scope> \
  --cache-mode max \
  --no-platform \
  --no-git \
  --fail-on-cache-error \
  -- docker compose --file <compose-file> <run-or-up-command>
```

The CLI resolves the Compose project and supplies a temporary per-service cache
override. Compose still owns the build, container lifecycle, health checks, and
local images; the proof does not translate MAE's project into a maintained Bake
file or add cache settings to its source.

The two `up --wait` cases preserve MAE's Makefile success contract: Compose may
return nonzero when the one-shot `verifier` service stops, so the harness accepts
that result only when the verifier's recorded exit code is zero. Other lifecycle
failures remain failures and include scoped Compose status and logs in the proof
artifact.

## Result

The Compose integration passed all three upstream workflows, but this is not an
outbound-ready cache win for MAE's current commit pattern.

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

## Runs

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

## Evidence

The upstream control is [MAE run 30300856171](https://github.com/cuttlefisch/mae/actions/runs/30300856171).
All BoringCache evidence is on the
[`mae-compose-proof` branch](https://github.com/boringcache/docker-cache-proofs/actions?query=branch%3Amae-compose-proof),
and every run above publishes its benchmark JSON and BuildKit log as workflow
artifacts.

The proof pins CLI `vcli-canary-851ae8ac013f` and BuildKit
`v0.30.0-bc.14@sha256:9b44a5426d7e32db41584c8d7d9f5251b0ad8348427e15849b541418030e7dab`.
The case files pin every source revision and use separate cache scopes for the
three Compose projects.

During setup, the headless service hit its own watchdog health timeout twice
before its verifier could start. The cache operation completed normally; the
exact-ref retry and all six chronological headless runs passed. Those setup
failures are [run 30639151606](https://github.com/boringcache/docker-cache-proofs/actions/runs/30639151606)
and [run 30640450349](https://github.com/boringcache/docker-cache-proofs/actions/runs/30640450349).

## What this would mean for MAE

This is a product-path validation, but not outbound-ready guidance today. MAE
could wrap its existing commands with the CLI without restructuring the
Dockerfile or committing cache backend configuration to the Compose files. The
fully warm result proves that path can remove almost all build work.

The recent rolling history is the blocker: every tested commit invalidated the
dependency layer, and the four waves stayed near cold-build time. The next
useful experiment would be a longer commit window containing ordinary source
changes that leave Cargo manifests and `Cargo.lock` untouched. Until that shows
repeatable rolling savings, the honest result is Compose compatibility rather
than a MAE cache recommendation.
