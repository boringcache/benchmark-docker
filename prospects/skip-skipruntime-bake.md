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

The five changed-source transitions had a 149-second median, 57% below the
343-second cold seed. That aggregate needs its shape stated plainly: the first
three transitions took 128–149 seconds, while changes that invalidated the
source-built compiler graph took 373 and 445 seconds. In the last transition,
the bootstrap compiler alone ran for 4m51s and the runtime build for 1m41s.
BoringCache cannot reuse a layer whose inputs genuinely changed.

The unchanged replay of the final revision took 11 seconds. It served 20 of 21
cache objects and reduced the graph to cached vertices plus sub-second metadata
and cache-export work. This demonstrates that the exact Bake graph is reusable
across fresh jobs; it does not promise that compiler changes become hot builds.

| Source | Complete Bake command |
|---|---:|
| [`34499568`](https://github.com/SkipLabs/skip/commit/34499568bb0d2da8f04173e4641cfa0c1e98050d) cold seed | [343s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30641966651) |
| [`5ae76355`](https://github.com/SkipLabs/skip/commit/5ae7635588faf91cfbe3e2a5c559d446f0f8dab7) | [149s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642470585) |
| [`0374dcbe`](https://github.com/SkipLabs/skip/commit/0374dcbe40821c65b1f2cc7ddcaa80efd0a56485) | [128s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642708165) |
| [`7c6bb5b1`](https://github.com/SkipLabs/skip/commit/7c6bb5b1664ada168e6491ead702a1a5966d069f) | [145s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30642910517) |
| [`53055d79`](https://github.com/SkipLabs/skip/commit/53055d79b1ea13f9e18bbdf1cbc40bfebc5deeb2), compiler invalidation | [373s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643141054) |
| [`1813f196`](https://github.com/SkipLabs/skip/commit/1813f196b481b24a08b6f418bd4d9f03d7849333), compiler invalidation | [445s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30643645532) |
| Unchanged `1813f196` replay | [11s](https://github.com/boringcache/docker-cache-proofs/actions/runs/30644217303) |

Each number is the complete measured `docker buildx bake` command, including
cache import and export. These are ordered transition samples, not repeated
statistical trials.

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
