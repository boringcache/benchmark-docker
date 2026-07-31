# Proteus multi-arch Docker cache proof

[Proteus reported](https://github.com/CraftingTech/proteus/issues/45) that its
multi-arch Rust image workflow ran for 4h36. The images reached GHCR, but the
job then failed while exporting a `type=gha,mode=max` cache with `not_found`.

We built Proteus's pinned source with a proof Dockerfile based on its deployment
stages to answer two questions:

- How much of the build time came from running ARM64 compilation through QEMU?
- How much could Docker layers, sccache, and Cargo `target` caches save on a
  later source change?

## Result

We moved AMD64 and ARM64 into two native GitHub-hosted jobs. They run in
parallel, push one image per architecture, and a final job joins them into the
same multi-arch image.

| Build | Runner layout | Result | Full workflow |
|---|---|---|---:|
| [Proteus run](https://github.com/CraftingTech/proteus/actions/runs/30160511674) | AMD64 runner, ARM64 through QEMU | Images pushed; GHA cache export failed | 4h36m27s |
| [Native cold seed](https://github.com/boringcache/docker-cache-proofs/actions/runs/30633095558) | Native AMD64 + native ARM64, in parallel | Image and cache published | 15m47s |
| [Native rolling commit](https://github.com/boringcache/docker-cache-proofs/actions/runs/30634211494) | Native AMD64 + native ARM64, in parallel | Image and cache published | 4m46s |

The native cold workflow used 94.3% less wall time than the QEMU workflow, a
17.5x speedup. Reusing its cache on a later Proteus commit reduced the complete
workflow by another 69.8%, a 3.3x speedup.

These are two different improvements. The cold result mostly comes from not
emulating ARM64. The rolling result shows the cache saving work between real
commits.

## QEMU and native build times

The original workflow built both platforms in one Buildx job. AMD64 ran
natively, while ARM64 ran through QEMU. The cold proof used one native runner
for each platform.

| Cold build step | Original AMD64 | Original ARM64 with QEMU | Proof AMD64 native | Proof ARM64 native |
|---|---:|---:|---:|---:|
| Install Dioxus CLI | 18m48s | 3h19m03s | 9m23s | 7m39s |
| Build the UI | 2m17s | 18m33s | 1m16s | 1m04s |
| Build the controller | 6m42s | 53m44s | 3m42s | 3m28s |

On ARM64, the native runner reduced these three Rust-heavy step times by 93.6%
to 96.2%. The two native jobs ran at the same time, so the full workflow waited
for the slower job rather than adding both build times together.

## Cache result

The rolling run built a later Proteus commit, not an unchanged replay. The
rolling ref is three commits ahead of the seed.

| Source | Commit | AMD64 build | ARM64 build | Full workflow |
|---|---|---:|---:|---:|
| Cold seed | `71ac73a73c99` | 897s | 767s | 15m47s |
| API resource-module refactor | `b3d6345e08cd` | 200s | 232s | 4m46s |
| Difference |  | 77.7% less | 69.8% less | 69.8% less |

Each rolling architecture reported:

- six cached BuildKit steps and a 98% cache-object hit rate;
- cache import and export under one second;
- two sccache hits from three executed Rust compiler requests;
- zero cache read or write errors.

The restored Cargo `target` caches carried most of the previous Rust work. They
remained stable after the rolling commit:

| Target cache | Compressed size | State |
|---|---:|---|
| AMD64 UI + controller | 399.6 MiB | Restored and republished |
| ARM64 UI + controller | 389.1 MiB | Restored and republished |

The three cache surfaces have separate jobs:

- BuildKit cache reuses complete Dockerfile steps.
- sccache reuses compiler objects when a Rust step has to run again.
- Cargo `target` mounts preserve incremental build state that is not part of a
  normal image layer.

## What we tested

The proof keeps Proteus's multi-stage image outcome and publishes a normal
AMD64/ARM64 manifest to GHCR.

- AMD64 runs on `ubuntu-24.04`.
- ARM64 runs on `ubuntu-24.04-arm`.
- The architecture jobs have separate BuildKit, sccache, and Cargo `target`
  cache identities.
- Dioxus CLI installation and both controller builds use sccache.
- `dx build` keeps Dioxus's own workspace compiler wrapper.
- Only the UI and controller `target` mounts are offloaded. Cargo registry and
  Git state remain ordinary Docker layer inputs.

The original and proof workflows do not use identical hardware or cache
layouts, so this is an operational comparison rather than a cache-only
benchmark. The cold run shows the native-runner gain. The rolling run measures
cache reuse from one Proteus commit to the next.

## Run it again

Use a new cache scope suffix so an older run cannot seed the result:

```bash
./scripts/dispatch-proof-series.sh \
  --case proteus-controller-multiarch \
  --ref main \
  --rolling-bootstrap-ref main \
  --rolling-ref rolling1 \
  --build-output ghcr \
  --lane-filter buildkit \
  --cache-scope-suffix proteus-rerun-1 \
  --rust-target-cache \
  --skip-fresh
```

The first run seeds the native architecture caches. The second checks out the
later Proteus commit and records BuildKit, sccache, Cargo `target`, image, and
manifest evidence.

## What this means for Proteus

Proteus does not need QEMU for this public repository. GitHub provides
[standard AMD64 and ARM64 hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
so each image can be built on its own architecture and joined afterward.

That changes the cold multi-arch workflow from 4h36 to about 16 minutes. On a
later commit, BoringCache reduced it to under five minutes and published the
cache without turning a successful image push into a failed job.
