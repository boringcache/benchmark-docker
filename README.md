# BoringCache Docker benchmark

This repository runs real, pinned Buildx workloads through BoringCache One.
Product behavior and evidence contracts are tested in the BoringCache product
repository; this repository owns only workload selection and source setup.

Run `Docker Product Proof` with a case and pinned source ref. The same workflow
supports both released and canary product lanes:

- leave `cli_version` and `buildkit_image` empty to use the action defaults;
- set `cli_version` to an exact prerelease CLI tag to test a CLI canary;
- set `buildkit_image` to an exact managed BuildKit image to test a backend
  canary;
- set both to prove the complete prerelease product pair.

`fresh` publishes once and restores on a new runner. `rolling` reuses a stable
case scope across commits. Product failures fail the workflow directly through
`fail-on-cache-error`; benchmark-local receipt or cache-internal assertions are
intentionally absent.

Workflow orchestration is in [`.github/workflows/`](.github/workflows/), case
metadata is in [`cases/`](cases/), and repository configuration is in
[`.boringcache.toml`](.boringcache.toml).
