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

The command below reproduces the recorded cohort with its immutable
Compose-capable CLI canary. Current product reruns can omit `--cli-version` to
select the released v1.16.3 CLI. Compose owns image materialization, so the
harness input remains `none` even though the measured lifecycle builds and
loads the local service image before startup.

```bash
./scripts/dispatch-proof-series.sh \
  --case vilnacrm-bootstrap-infrastructure \
  --ref agent/vilnacrm-compose-proof \
  --rolling-bootstrap-ref seed \
  --lane-filter buildkit \
  --cli-version vcli-canary-6636517dfa2d \
  --cache-scope-suffix vilna-r3 \
  --warm-replay \
  --skip-fresh
```

## Result

This proof did not clear its acceptance threshold. The four rolling revisions
with unchanged Docker inputs took 36, 40, 36, and 36 seconds: a 36-second
median, effectively the same as the roughly 37-second upstream average. The
`uv.lock` change then took 56 seconds, and an unchanged replay of that revision
took 39 seconds. Remote layer reuse works, but cache setup, image load, and
container startup leave no material end-to-end saving for this already-short
lifecycle.

| Source | Complete prepare / Compose build-load-start |
|---|---:|
| [`b01b2e22`](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/commit/b01b2e22a341) cold seed | [70s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642677359) |
| [`84f72466`](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/commit/84f72466ce76) | [36s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642835955) |
| [`b8efa3b7`](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/commit/b8efa3b71dcb) | [40s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642924268) |
| [`2eb40b76`](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/commit/2eb40b76d139) | [36s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643010945) |
| [`a497c6e4`](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/commit/a497c6e42626) | [36s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643133909) |
| [`d3015695`](https://github.com/VilnaCRM-Org/bootstrap-infrastructure/commit/d3015695def1), `uv.lock` change | [56s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643229640) |
| Unchanged `d3015695` replay | [39s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643358171) |

The honest recommendation is a digest-pinned, scanned development image that
the fan-out jobs pull directly. That removes the repeated build and tooling
setup rather than placing a remote cache in front of a small build.

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

- [Controlled rolling series](https://github.com/boringcache/docker-cache-proofs/actions?query=branch%3Aagent%2Fvilnacrm-compose-proof+event%3Aworkflow_dispatch)
