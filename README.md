# docker-cache-proofs

Public benchmark runner for comparing Docker and build caches on real upstream projects.

Each case pins an upstream repository and source revision so fresh and rolling runs remain reproducible.

## Source Model

- Docker cases live in [`cases/`](cases/).
- Cases use upstream Dockerfiles and build contexts unless an explicit benchmark overlay is part of the case.
- Multi-image cases can use an explicit Bake overlay while keeping the pinned upstream Dockerfiles and contexts unchanged.
- Compose cases keep the upstream lifecycle command and let the CLI add a temporary per-service cache override.

## What It Measures

Docker cases compare:

- GitHub Actions Cache
- BoringCache's CLI-managed BuildKit backend

Fresh runs seed an isolated cache from the pinned source. Rolling runs build a later pinned revision against the same stable cache scope.

### BIAR Spark-stack proof

The three BIAR cases reproduce the large images reported in
[tazama-lf/biar#142](https://github.com/tazama-lf/biar/issues/142). Each case
pins the same upstream commit while keeping the image's original Dockerfile,
context, platform, and independent cache identity. The controlled series seeds
a new BoringCache scope and then replays the unchanged source so the result
measures full-cache behavior beyond BIAR's shared default GHA cache allowance.

The protocol and upstream evidence are documented in
[`prospects/biar-spark-images.md`](prospects/biar-spark-images.md).

Rust cases that declare a Cargo target cache mount can also run a paired target
proof. The ordinary BoringCache lane remains the product control. The target
lane enables the managed BuildKit cache-mount offloader, keeps an independent
cache scope, and records the target archive's compressed bytes, logical bytes,
file count, and rolling growth. Iggy, Wormhole, and Proteus currently expose
this proof; other cases fail early rather than silently running without target
evidence.

### Proteus multi-arch Rust proof

The `proteus-controller-multiarch` case starts from the exact commit in
[CraftingTech/proteus#45](https://github.com/CraftingTech/proteus/issues/45).
That upstream run pushed both image tags, then failed after 4h36 when its
`type=gha,mode=max` cache export returned `not_found`.

The proof keeps the distroless runtime and the original amd64 + arm64 output,
but replaces emulation with parallel native GitHub-hosted runners:

- amd64 runs on `ubuntu-24.04` and arm64 runs on `ubuntu-24.04-arm`;
- each native lane builds and pushes one architecture-specific image, after
  which the final job joins those tags into one manifest;
- BoringCache's managed BuildKit backend owns the ordinary OCI layer cache;
- `--tool-cache sccache` reuses compiler outputs for the Dioxus CLI and both
  native controller builds, while only Dioxus's workspace wrapper stays outside
  sccache; and
- the target variant offloads the UI and per-architecture controller
  `/src/target` cache mounts and records their compressed bytes, logical bytes,
  file counts, and growth; Cargo registry/git state stays in ordinary Docker
  layers so the target evidence contains only the two caches being claimed.

Run the native amd64 + arm64 BoringCache matrix and its additional target-mount
lane. Each job pushes its architecture image to GHCR, then a final job publishes
their shared multi-arch manifest:

```sh
./scripts/dispatch-proof-series.sh \
  --case proteus-controller-multiarch \
  --build-output ghcr \
  --compare-rust-target \
  --warm-replay
```

Run an ordered pure-versus-target series with:

```sh
./scripts/dispatch-proof-series.sh \
  --case iggy-rust-server \
  --compare-rust-target
```

The target state is only a performance input. Builds must still be correct from
an empty mount because BuildKit may garbage-collect native cache mounts.
GitHub's `type=gha` exporter does not preserve cache-mount contents, so the
ordinary GHA lane runs once as the external-cache control; the target variant
adds only the isolated BoringCache offload lane.

Some cases also compare against a GHCR registry cache. These runs use one stable
tag and record the export time and package versions left behind when the tag is
replaced.

GHCR is only a comparison. BoringCache always uses its normal product path: the
CLI manages the builder and uses the native `type=boringcache` exporter.

## Prospect Reports

- [MediSwarm classic Docker cache proof](prospects/mediswarm-classic-build.md)
  tests ODELIA and STAMP as separate remote caches across builder pruning and
  five consecutive upstream source transitions.
- [Grafana Cloud Cost Exporter Docker and Go cache proof](prospects/cloudcost-exporter.md)
  compares GitHub Actions Cache, BoringCache Docker, and BoringCache Docker + Go
  across five consecutive upstream source transitions.
- [Posit Connect content layer-cache proof](prospects/posit-connect-content.md)
  isolates the cache-backend part of Posit's registry-rate-limit work without
  claiming to replace temporary, SOCI, or published image storage.
- [Bluesky Tiled multi-platform container proof](prospects/tiled-container-canary.md)
  isolates the first rolling image build from Tiled's later same-job cache
  overwrite and compares cache transport across four upstream transitions.

## Workflows

- [`Docker Benchmark`](.github/workflows/docker-cache-proofs.yml)
- [`Canary Benchmark`](.github/workflows/canary-dispatch.yml) runs the selected canary CLI and BuildKit image against the curated Docker cases in [`.canary/candidates.txt`](.canary/candidates.txt).

## Output

Each run uploads machine-readable JSON and Markdown summaries using the same artifact shape as the other BoringCache benchmark repositories.

## Prospect proofs

- [Mozilla Experimenter Bake proof](prospects/mozilla-experimenter.md)
- [MAE Docker Compose proof](prospects/mae-compose.md)
- [LegalQuants lq-ai Docker Compose proof](prospects/legalquants-compose.md)
- [VilnaCRM Compose proof](prospects/vilnacrm-compose.md)
- [Blockscout frontend proof](prospects/blockscout-frontend.md)
- [terraform-aws-cli matrix proof](prospects/terraform-aws-cli.md)
