# LegalQuants lq-ai Docker Compose cache proof

[lq-ai issue #298](https://github.com/LegalQuants/lq-ai/issues/298) records a
20–30 minute cold Compose build and rejects GitHub Actions Cache because its
10 GB project limit churns the large Torch, CUDA, and Docling layers.

That historical number is no longer the honest current baseline. The project
later moved the API and gateway images to locked `uv sync` builds in
[`c177f36f`](https://github.com/LegalQuants/lq-ai/commit/c177f36fd2c7e4e16bf234d8479dac2ae61986ba).
Recent complete stack-smoke jobs are about nine minutes, with about five minutes
in the image-build phase.

## Current upstream evidence

| Upstream run | Complete job | Stack-smoke script | Two build commands |
|---|---:|---:|---:|
| [July 30](https://github.com/LegalQuants/lq-ai/actions/runs/30588730406/job/91026077028) | 9m07s | 7m26s | 5m10s |
| [July 29](https://github.com/LegalQuants/lq-ai/actions/runs/30555624031/job/90915206308) | 9m04s | 7m14s | 4m59s |
| [July 6](https://github.com/LegalQuants/lq-ai/actions/runs/28951245358/job/85898251800) | 11m54s | 8m03s | 5m54s |

In the July 30 run, the web image spent 86.2 seconds installing its Python and
Torch dependencies and 182.3 seconds building the frontend, then 21.1 seconds
exporting. The API image's locked dependency sync took 32.9 seconds and its
export took 15.2 seconds. These are useful targets, but the controlled proof
must report the complete Compose command and job wall time too.

## Preserve the upstream build shape

The upstream `scripts/stack-smoke.sh` deliberately runs:

```sh
docker compose build gateway web
docker compose build api
docker tag lq-ai-api:latest lq-ai-ingest-worker:latest
docker tag lq-ai-api:latest lq-ai-arq-worker:latest
```

API, ingest-worker, and arq-worker share one build context and produce the same
large image. Building them together can export that roughly 12 GB image three
times and exhaust runner disk, so the script builds API once and tags it for
the workers.

The one-command proof harness therefore exposes two cases rather than replacing
the safe sequence with `docker compose build`:

- `legalquants-gateway-web` runs `docker compose build gateway web`.
- `legalquants-api` runs `docker compose build api`.

They run as separate benchmark jobs, so their times should be read as two
components of the upstream build phase, not summed into a claim about a single
measured job. Both retain the upstream disk cleanup and the exact boot-only
dummy `.env` values before Compose resolves the project. The worker tags and
the later boot/health/soak lifecycle do not build new layers and remain outside
this cache-backend proof.

## Rolling checkpoints

Both cases use the same selected first-parent checkpoints:

| Case ref | Upstream revision | Relevant change since the previous checkpoint |
|---|---|---|
| `seed` | [`8179c8af`](https://github.com/LegalQuants/lq-ai/commit/8179c8af53f2dca41d523f35633caae82bf0af00) | Gateway cryptography dependency |
| `rolling1` | [`d9760abf`](https://github.com/LegalQuants/lq-ai/commit/d9760abf54d9f879581d3df62556e0d753221ccf) | Gateway FastAPI dependency |
| `rolling2` | [`8edd043e`](https://github.com/LegalQuants/lq-ai/commit/8edd043e545f62ee95969c86826cbe855a3e5d72) | Web test configuration and gateway Starlette dependency |
| `rolling3` | [`ea9b6e76`](https://github.com/LegalQuants/lq-ai/commit/ea9b6e7679ff08caf767a7bd63c2727ed5d389c8) | Gateway dependency updates and API aioboto3 dependency |
| `rolling4` | [`1d7f9f30`](https://github.com/LegalQuants/lq-ai/commit/1d7f9f30327c85635175bcf0799bb14c90f4e5ec) | Workflow changes and API dependency sweep |
| `rolling5` | [`b060ae2f`](https://github.com/LegalQuants/lq-ai/commit/b060ae2faf17a946cdfa6d3b0740c955ff2600bb) | Gateway SQLAlchemy dependency and runtime security change |

These are ordered checkpoints, not consecutive commits. They intentionally
exercise dependency changes in both proof components while keeping the series
short enough to repeat. Unchanged-component checkpoints are useful: they show
whether the remote cache can restore a large image when only the other service
changed.

Compose support is currently a CLI canary feature. Pin the immutable canary so
the proof does not change underneath the rolling series:

```sh
./scripts/dispatch-proof-series.sh \
  --case legalquants-gateway-web \
  --rolling-bootstrap-ref seed \
  --lane-filter buildkit \
  --build-output none \
  --cache-scope-suffix legalquants-gateway-web-1 \
  --cli-version vcli-canary-6636517dfa2d \
  --skip-fresh

./scripts/dispatch-proof-series.sh \
  --case legalquants-api \
  --rolling-bootstrap-ref seed \
  --lane-filter buildkit \
  --build-output none \
  --cache-scope-suffix legalquants-api-1 \
  --cli-version vcli-canary-6636517dfa2d \
  --skip-fresh
```

The CLI resolves the existing Compose services and adds a temporary cache
override with independent service tags. It does not edit lq-ai's Compose file,
change its Dockerfiles, or translate the build into a maintained Bake file.

## Credential boundary

The appropriate first adoption target is trusted `main` or a manual internal
benchmark. Ordinary repository secrets are not available to Dependabot and
must not be exposed to untrusted fork pull requests. Dependabot could receive a
separate read-only secret only after an explicit policy decision; fork builds
should stay cold or fail open. BoringCache does not remove that trust boundary,
and this proof does not claim otherwise.
