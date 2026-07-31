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
cached step count, and retained cache bytes. The GHCR breakdown additionally
records the active manifest size, the package's tagged and untagged version
counts, and retained bytes deduplicated by blob digest across every manifest.

## Results

Pending the controlled rolling series.
