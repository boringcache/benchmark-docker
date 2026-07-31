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

## Result

Pending the isolated seed, changed-source rolling build, and unchanged-source
warm replay.

## Evidence

Upstream control: [MAE run 30300856171](https://github.com/cuttlefisch/mae/actions/runs/30300856171).

BoringCache runs and artifacts are pending.

## What this would mean for MAE

This is a product-path validation, but not outbound-ready guidance yet. If the
three proofs retain their Compose lifecycle behavior and materially reduce the
rolling critical path, MAE can use the same CLI wrapper around its existing
commands without restructuring the Dockerfile or committing cache backend
configuration to the Compose files.
