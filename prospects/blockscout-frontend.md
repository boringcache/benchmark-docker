# Blockscout frontend Docker cache proof

This proof follows [blockscout/frontend#3602](https://github.com/blockscout/frontend/issues/3602),
where the first measured GHCR `mode=max` cache export took 150.8 seconds and
replaced a cache tag without reclaiming the now-untagged manifest.

## Prospect question

Can BoringCache shorten the cache-export tail and avoid the registry-tag
lifecycle that leaves old GHCR cache manifests retained?

The proof compares two cache transports on the same GitHub-hosted runner class,
Dockerfile, build arguments, platform, source commit, and BuildKit image:

- GHCR registry cache, using the upstream `mode=max`, OCI media type, and image
  manifest settings against one stable rolling tag.
- BoringCache's CLI-managed BuildKit backend, using its native
  `type=boringcache` exporter and one stable rolling cache scope.

The control omits upstream's `ignore-error=true` because a proof must fail when
the cache export fails; its transport, `mode=max`, OCI media type, and image
manifest behavior otherwise match the upstream cache.

The GHCR control is intentionally opt-in. It is not an alternate BoringCache
product path and does not change the repository's default GHA-vs-BoringCache
proof pair.

## Rolling source sequence

| Ref | Commit | Upstream change |
|---|---|---|
| `seed` | `8d6e447a60c4` | Exclude agent worktrees from lint and test runners |
| `rolling1` | `c3b79a0787b2` | Prometheus registry fix |
| `rolling2` | `a204400d1a46` | Shared agent rules reorganization |
| `rolling3` | `3e8f4939ab7b` | Merge the corepack retry and GHCR cache write-back change |
| `rolling4` | `39bb7b3e6e5d` | Worktree dependency and pruning hooks |
| `rolling5` | `da93fdec5b11` | `dotenv-cli` and lockfile update |

This is first-parent order on Blockscout's `main` branch. It includes ordinary
source/configuration churn, the Dockerfile/cache change that prompted the issue,
and a dependency lockfile change.

## Run protocol

Use a unique scope suffix for the series. Skip the separate fresh lane, seed the
stable rolling scope at `seed`, advance through every pinned commit, and replay
the final commit once to measure a no-source-change warm build:

```bash
./scripts/dispatch-proof-series.sh \
  --case blockscout-frontend \
  --ref blockscout-frontend-proof \
  --rolling-bootstrap-ref seed \
  --lane-filter registry-buildkit \
  --cache-scope-suffix prospect-20260731 \
  --skip-fresh \
  --warm-replay
```

Each run records total and BuildKit wall time, cache import and export time,
and cached step count. The GHCR breakdown additionally records the active
manifest size, the package's tagged and untagged version counts, and retained
bytes deduplicated by blob digest across every manifest. BoringCache lifecycle
evidence comes from the product's cache-entry inventory because its shared CAS
accounting is not byte-for-byte comparable with a GHCR package.

## Results

The controlled series ran on 31 July 2026. Every paired row used the same
`ubuntu-latest` runner class, source commit, upstream Dockerfile, build
arguments, `linux/amd64` platform, custom BuildKit image, and `output=none`.
`Build` is the wall time of one `docker buildx build`; `export` is the measured
cache-export tail within that time.

| Source | Evidence | Cached steps (BC / GHCR) | Build (BC / GHCR) | Export (BC / GHCR) | GHCR retained | Versions (untagged) |
|---|---|---:|---:|---:|---:|---:|
| Bootstrap `8d6e447a60c4` | [run 30624162195](https://github.com/boringcache/docker-cache-proofs/actions/runs/30624162195) | 0 / 0 | 443s / 637s | 2.7s / 258.7s | 1.94 GiB | 1 (0) |
| Rolling 1 `c3b79a0787b2` | [run 30624838863](https://github.com/boringcache/docker-cache-proofs/actions/runs/30624838863) | 26 / 29 | 453s / 688s | 3.0s / 313.1s | 3.71 GiB | 2 (1) |
| Rolling 2 `a204400d1a46` | [run 30625573930](https://github.com/boringcache/docker-cache-proofs/actions/runs/30625573930) | 26 / 28 | 465s / 646s | 3.2s / 256.2s | 5.47 GiB | 3 (2) |
| Rolling 3 `3e8f4939ab7b` | [run 30627441739](https://github.com/boringcache/docker-cache-proofs/actions/runs/30627441739) | 21 / 21 | 468s / 632s | 3.5s / 246.9s | 7.35 GiB | 4 (3) |
| Rolling 4 `39bb7b3e6e5d` | [run 30628168268](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628168268) | 26 / 27 | 478s / 635s | 3.1s / 255.8s | 9.11 GiB | 5 (4) |
| Rolling 5 `da93fdec5b11` | [run 30628873391](https://github.com/boringcache/docker-cache-proofs/actions/runs/30628873391) | 15 / 13 | 448s / 701s | 2.7s / 278.0s | 10.88 GiB | 6 (5) |
| Exact warm replay | [run 30629682491](https://github.com/boringcache/docker-cache-proofs/actions/runs/30629682491) | 55 / 55 | 15s / 13s | 1.0s / 6.0s | 10.88 GiB | 7 (6) |

### Rolling-build result

Across the five real commit-to-commit builds, BoringCache averaged 462.4
seconds against GHCR's 660.4 seconds. That is 198 seconds saved per build, or a
30.0% reduction in measured `buildx` wall time.

The difference is concentrated in the write-back path. BoringCache's final
export averaged 3.1 seconds; GHCR averaged 270.0 seconds. The BoringCache tail
was 87x shorter. GHCR export consumed 40.9% of its measured build time across
the rolling sequence, while the BoringCache export consumed 0.7%.

This is not a cache-hit-quality trick: both lanes reused a similar number of
BuildKit steps on every rolling commit. The `3e8f4939ab7b` row is the upstream
merge containing the Dockerfile/corepack and GHCR cache write-back change that
prompted issue #3602; the result persisted on that commit and the two commits
after it.

### Fully warm result

The final no-source-change replay cached all 55 BuildKit steps in both lanes.
BoringCache spent 0.3 seconds importing and 1.0 second exporting; GHCR spent
4.2 seconds importing and 6.0 seconds exporting. That is 1.3 seconds versus
10.2 seconds of measured cache transport. The complete jobs finished in 30 and
43 seconds respectively, a 13-second or 30% end-to-end reduction.

The replay's `buildx` wall time alone was 15 seconds for BoringCache and 13
seconds for GHCR, a two-second runner-level reversal. The warm-build claim is
therefore about the directly measured transport and complete job, not a claim
that BoringCache made already-cached application work faster.

### Storage and lifecycle result

GHCR retained storage grew from 1.94 GiB after the bootstrap to 10.88 GiB after
the five rolling commits, even though the active cache graph remained about
1.93 GiB. The stable tag produced six package versions, five of them untagged.
After the identical replay, GHCR had seven versions and six untagged manifests;
the replay added only 64,461 bytes because its blobs were unchanged.

The final GHCR package retained 5.63x the bytes in its active graph. These are
digest-deduplicated totals across all package versions, so shared blobs are
counted once rather than once per manifest.

BoringCache's product inventory showed one current rolling tag pointing at a
1,946,046,627-byte (1.81 GiB), 60-blob CAS graph. Older graphs no longer held
the current tag. This is the lifecycle wedge: Blockscout can stop publishing
registry-cache package versions and move retention and content deduplication
under BoringCache's managed CAS lifecycle.

The generic benchmark artifact reported zero BoringCache-attributable bytes
for this shared CAS tag. That does **not** mean the cache occupied zero bytes;
the product inventory above is the authoritative logical graph size. Because
the BoringCache graph and GHCR package use different accounting, the storage
claim is the demonstrated GHCR retained-to-active growth and the removal of its
untagged-package lifecycle—not a byte-for-byte billing comparison.

## Prospect case

Blockscout's own first successful `mode=max` run spent 150.8 seconds exporting
cache, 31% of a 7m57s job. This reproduction found the same problem across a
real six-commit progression: GHCR's warm rolling exports took 246.9–313.1
seconds, while BoringCache's took 2.7–3.5 seconds.

The proposed change is narrow: replace the workflow's `type=registry` cache
import/export with BoringCache's managed BuildKit path. The application
Dockerfile, layer model, build arguments, platform, and image output do not need
to change. On this measured sequence, that removes roughly 3m18s from an
average rolling build and removes GHCR cache-package tags and their untagged
manifest cleanup from Blockscout's workflow.
