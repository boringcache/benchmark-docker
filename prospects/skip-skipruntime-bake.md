# Skip native runtime Bake cache proof

[Skip issue #1364](https://github.com/SkipLabs/skip/issues/1364) reports that
the native runtime test spent 316.6 seconds of a 589.4-second CircleCI job
building `libskipruntime.so`. The issue-era build spent 155.5 seconds compiling
the bootstrap toolchain and 91.6 seconds compiling the runtime.

The pain remains visible in recent branch jobs. One
[July 29 job](https://circleci.com/gh/SkipLabs/skip/19676) took 631.3 seconds;
its native runtime step took 362.3 seconds, including a 192-second bootstrap
compiler layer and a 91.2-second runtime layer.

## What this proof tests

The proof runs Skip's `skipruntime` target from the upstream
`docker-bake.hcl`. That target preserves the important named-context edge:

```hcl
contexts = {
  "skiplabs/skiplang-bin-builder" = "target:skiplang-bin-builder"
}
```

This makes Bake build `skiplang/Dockerfile` from the checked-out source before
`skipruntime-ts/Dockerfile`. Pointing a plain `docker buildx build` at the
runtime Dockerfile would pull the published builder image and omit the measured
bootstrap work.

The measured command is equivalent to:

```bash
boringcache docker \
  --workspace boringcache/docker-cache-proof \
  --tag <scope> \
  --cache-mode max \
  --no-platform \
  --no-git \
  --fail-on-cache-error \
  -- docker buildx bake \
    --file docker-bake.hcl \
    --progress=plain \
    --set '*.platform=linux/amd64' \
    --set 'skiplang-bin-builder.args.SKIP_CAPACITY=6G' \
    --set 'skipruntime.args.SKIP_CAPACITY=6G' \
    skipruntime
```

The proof pins `vcli-canary-851ae8ac013f`, an immutable CLI canary containing
the Bake planner. It checks out the two Skip submodules consumed by the graph
and requests no image output, so the measurement covers the compiler and
runtime solves plus cache publication.

## Intentional policy change

Skip's current `bin/docker_build.sh` passes `--no-cache` for ordinary local
builds. This proof intentionally omits that flag. A remote cache cannot produce
hits while `--no-cache` remains in the command, so the benchmark tests the
policy change proposed in issue #1364 rather than pretending BoringCache can
override it.

The rolling sequence contains changes to copied `skipruntime-ts` sources,
followed by bootstrap and compiler changes. That exercises both expensive
parts of the graph instead of replaying workflow-only commits.

## Result

Pending an isolated seed, five rolling source transitions, and an unchanged
current-main replay.

## Trust boundary

This is a proof-repository change, not an upstream Skip pull request. CircleCI
does not pass project secrets to fork pull requests by default. A later
integration could cache trusted branches and internal pull requests, while
untrusted fork builds remain cold or fail open; BoringCache credentials must
not be exposed to fork-controlled code.

The current signed BoringCache CLI release does not include the Bake planner.
An upstream proposal should wait for a signed release and for Skip's
maintainers to approve removing `--no-cache` on the trusted lane.

## Run it

Use a new suffix so no older proof can seed the result:

```bash
./scripts/dispatch-proof-series.sh \
  --case skip-skipruntime-bake \
  --ref agent/skip-bake-proof \
  --rolling-bootstrap-ref seed \
  --lane-filter buildkit \
  --cache-scope-suffix skip-runtime-rolling-1 \
  --skip-fresh \
  --warm-replay
```

The case manifest supplies the immutable CLI canary when the workflow input is
left empty.
