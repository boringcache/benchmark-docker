# terraform-aws-cli Docker cache proof

[terraform-aws-cli issue #150](https://github.com/bgauduch/terraform-aws-cli/issues/150)
describes a 16-combination release matrix that can produce 15–25 GB of cache.
The project uses GitHub Actions Cache, but branch scoping and the repository
cache limit make it hard to keep the full matrix warm.

We ran the same 16 Terraform/AWS CLI combinations across four pinned source
revisions. Each build targeted `linux/amd64`, `linux/arm64`, `linux/arm/v7`,
and `linux/386` using the upstream Dockerfile.

## Result

| Average across 64 paired builds | GitHub Actions Cache | BoringCache | Difference |
|---|---:|---:|---:|
| Build time | 15m11s | 4m21s | 10m50s less (71%) |
| Cache export | 7m13s | 1.6s | 265x shorter |

BoringCache was faster in all 64 paired builds.

`Build time` is one `docker buildx build`, including cache export. The values
above are averages per matrix cell.

## Matrix critical path

The critical path is the slowest of the 16 builds in each wave.

| Source | GitHub Actions Cache | BoringCache | Saved | Evidence |
|---|---:|---:|---:|---|
| Seed | 19m34s | 9m20s | 10m14s (52%) | [GHA max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625647888), [BC max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625709158) |
| Rolling 1 | 17m54s | 3m49s | 14m05s (79%) | [GHA max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627511719), [BC max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627603611) |
| Rolling 2 | 17m01s | 3m42s | 13m19s (78%) | [GHA max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30629309365), [BC max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30629223889) |
| Rolling 3 | 34m37s | 3m32s | 31m05s (90%) | [GHA max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30630546715), [BC max](https://github.com/boringcache/docker-cache-proofs/actions/runs/30630666166) |

## What we tested

Both sides used the same GitHub-hosted `ubuntu-22.04` runner class, QEMU setup,
source revision, Dockerfile, build arguments, four target platforms, and
`output=none`.

- Each Terraform/AWS CLI combination kept one stable cache scope across the
  four source revisions.
- GitHub Actions Cache used `type=gha,mode=max`.
- BoringCache used its CLI-managed BuildKit backend.
- No Docker tool cache or Dockerfile changes were used.
- Registry push time was left out on both sides.

Parallel jobs did not share layers that were still being built. This proof
measures cache retention, reuse, and export across the rolling revisions.

The pinned case is
[`terraform-aws-cli-release-matrix.json`](https://github.com/boringcache/docker-cache-proofs/blob/prospect-sweep-2-proofs/cases/terraform-aws-cli-release-matrix.json).
All runs are public on the
[`prospect-sweep-2-proofs` branch](https://github.com/boringcache/docker-cache-proofs/actions?query=branch%3Aprospect-sweep-2-proofs).

## What this means for terraform-aws-cli

The release matrix can keep its Dockerfile, build arguments, and target
platforms. BoringCache replaces the GitHub Actions cache import and export
without adding registry cache tags to manage.
