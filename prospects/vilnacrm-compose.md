# VilnaCRM Compose cache proof

[VilnaCRM issue #128](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/issues/128)
asks whether the Pulumi development image can be reused across CI jobs. The
important cost is repetition, not a slow critical path: one representative pull
request launched 12 workflow runs whose 22 `make start` steps took 30–41 seconds
each, 811 seconds (13m31s) of aggregate runner time.

The cold path already satisfies the issue's sub-minute target. This proof is
therefore conditional: the remote cache is useful only if its build, local image
load, and container startup boundary is materially faster than the current
roughly 37-second average.

## What this proof tests

The proof preserves the build-owning part of `make start`:

1. `python3 ./scripts/prepare_docker_context.py`
2. `docker compose --file docker-compose.yml up -d`

The preparation command remains inside the timed lifecycle. It creates the
same private `.env`, `.pulumi-backend`, and `~/.aws` paths as upstream. Compose
still owns the local image load and starts the `pulumi` service; this is not an
output-less `docker buildx build`. The Compose definition keeps its `dev`
target, `UID`, `GID`, and `USERNAME=dev` build arguments. The harness exports
the runner UID/GID like the Makefile and fixes the proof to the native
`linux/amd64` GitHub-hosted runner.

The rolling series starts at `b01b2e22a341`, then builds `84f72466ce76`,
`b8efa3b71dcb`, `2eb40b76d139`, `a497c6e42626`, and `d3015695def1` in order.
The first four transitions leave the Docker build inputs unchanged. The final
transition changes `uv.lock`, providing one real dependency-input invalidation
after the stable toolchain layers have had a chance to hit.

The upstream baseline is no persistent cache. The proof does not label GitHub
Actions Cache as upstream, and it does not claim native uv caching. An unchanged
`uv.lock` can reuse the completed Docker layer; a changed lockfile may rerun
`uv sync` because BuildKit cache-mount contents are a separate surface.

## Run it

Use an isolated suffix and the immutable Compose-capable CLI canary. Compose
owns image materialization, so the harness input remains `none` even though the
measured lifecycle builds and loads the local service image before startup.

```bash
./scripts/dispatch-proof-series.sh \
  --case vilnacrm-bootstrap-infrastructure \
  --ref agent/vilnacrm-compose-proof \
  --rolling-bootstrap-ref seed \
  --lane-filter buildkit \
  --cli-version vcli-canary-851ae8ac013f \
  --cache-scope-suffix vilnacrm-rolling-1 \
  --warm-replay \
  --skip-fresh
```

## Result

Pending the isolated seed, five changed-commit builds, and unchanged final
replay. A useful result should move the complete build/load/start boundary
materially below 20 seconds or demonstrate enough aggregate savings across the
22-job fan-out to justify the remote-cache setup. Otherwise a digest-pinned,
scanned development image is the better recommendation.

## Upstream trust boundary

An adoption patch should let one trusted default-branch job publish the cache.
Ordinary pull-request jobs should receive only a restore token and remain
read-only, avoiding cache-poisoning and 22 concurrent writers. Fork and
Dependabot pull requests do not receive that credential and should stay cold
with a fail-open fallback. The integration must not use `pull_request_target`
to expose cache credentials to checked-out pull-request code.

This cache is not a deployable image registry and does not replace VilnaCRM's
image scanning or publication controls.

## Evidence

- [Issue #128](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/issues/128)
- [Representative pull-request workflow group](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/actions/runs/29125489822)
- [Security workflow from the same pull request](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/actions/runs/29125489945)
- [Guardrails workflow from the same pull request](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/actions/runs/29125489785)
- [Representative 39-second `make start` job](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/actions/runs/29125489822/job/86470056843)

BoringCache run artifacts are pending.
