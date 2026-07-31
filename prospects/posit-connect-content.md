# Posit Connect content layer-cache proof

[images-shared issue #681](https://github.com/posit-dev/images-shared/issues/681)
proposes moving Posit's BuildKit cache away from GHCR. The broader
[issue #679](https://github.com/posit-dev/images-shared/issues/679) also covers
temporary images and reports GHCR `toomanyrequests` failures across the image
matrix.

One issue-linked
[Connect job](https://github.com/posit-dev/images-connect/actions/runs/30313698156/job/90283968450)
ran for 7m30s. Its build step failed after 6m39s while several image targets
pushed temporary manifests to `ghcr.io/posit-dev/connect-content/tmp`.

## What this proof tests

The proof isolates one representative native Buildx target from that matrix:

- `connect-content/matrix/Containerfile.ubuntu2404.base` from
  `posit-dev/images-connect`;
- `linux/amd64` with the current R 4.6.1, Python 3.14.6, and Quarto 1.10.18
  build arguments; and
- `output=none` for both cache backends, so image publication is outside the
  measurement.

The Dockerfile installs Python through uv, Ubuntu packages, R, Quarto, and
TinyTeX. Its remote `ADD` of the latest TinyTeX release is intentionally left
unchanged; if that release moves, the downstream TinyTeX layer should rebuild.

The rolling sequence starts at an immutable seed and follows source commits
that changed this Dockerfile. The final current-main replay checks whether the
unchanged target remains reusable after unrelated repository changes.

## Result

Pending the isolated seed, three Dockerfile-changing rolling builds, and the
current-main replay.

## Scope boundary

This proof answers only the layer-cache part of issue #681. It compares Posit's
per-platform GHCR `type=registry,mode=max` cache with BoringCache's managed
BuildKit cache.

It does not replace or benchmark:

- the `/tmp` images used to merge native platform builds;
- SOCI artifacts; or
- final image publication to GHCR or Docker Hub.

Those are registry outputs, not BuildKit cache exports. The exact failures in
issue #679 occurred while pushing temporary and SOCI manifests, so a successful
layer-cache proof must not be presented as a complete fix for that issue.

## Run it

Use a new suffix so no earlier proof can seed the series:

```bash
./scripts/dispatch-proof-series.sh \
  --case posit-connect-content-amd64 \
  --ref agent/posit-connect-proof \
  --rolling-bootstrap-ref seed \
  --lane-filter registry-buildkit \
  --cache-scope-suffix posit-connect-rolling-1 \
  --skip-fresh \
  --warm-replay
```

The GHCR lane is a cache-package control only. Neither lane pushes a runnable
image.
