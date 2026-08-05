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

The four changed-commit transitions completed successfully in both lanes.
Their median measured BuildKit command was 66 seconds with BoringCache versus
80.5 seconds with the existing GHCR registry cache, an 18% reduction. The
unchanged current-main replay was effectively tied at 75 versus 74 seconds, so
the result is a lower transport cost across real changes rather than a claim
that BoringCache makes an already-hot no-op solve faster.

| Source | GHCR registry cache | BoringCache |
|---|---:|---:|
| [`caa8c46e`](https://github.com/posit-dev/images-connect/commit/caa8c46ecba63a8e1092bd5316e6e0041258ddde) cold seed | [210s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641960864) | [160s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641960864) |
| [`a73b3390`](https://github.com/posit-dev/images-connect/commit/a73b3390d574f7a150e2b73f4637270bea9d7f4f) | [184s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642341691) | [147s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642341691) |
| [`b29a5dc6`](https://github.com/posit-dev/images-connect/commit/b29a5dc63b1a170cc478f1de149fddf7dbae6458) | [83s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642642336) | [68s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642642336) |
| [`06a2999c`](https://github.com/posit-dev/images-connect/commit/06a2999cd4de9d95d893109386ea39963ae5ba16) | [78s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642873670) | [64s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642873670) |
| [`a629ff88`](https://github.com/posit-dev/images-connect/commit/a629ff884db05c69d7947dca6ae6113db6b915cf) | [76s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643095125) | [64s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643095125) |
| Unchanged `a629ff88` replay | [74s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643253701) | [75s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643253701) |

Each value is the measured `docker buildx build`, including cache import and
export. These are ordered transition samples, not repeated statistical trials.

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
gh workflow run docker-cache-proofs.yml \
  -f case_id=posit-connect-content-amd64 \
  -f ref_key=main \
  -f cache_lane=rolling \
  -f build_output=none \
  -f cache_scope_suffix=posit-connect-rolling-1
```

The GHCR lane is a cache-package control only. Neither lane pushes a runnable
image.
