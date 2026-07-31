# Mozilla Experimenter Docker Bake cache proof

[Experimenter issue #16332](https://github.com/mozilla/experimenter/issues/16332)
reports that about 22 CI jobs rebuild the same Docker layers. Its
`setup-cached-build` action builds `megazords`, `schemas`, and `cirrus`, then
jobs build an Experimenter test, development, or deployment image. The issue
measured 2–3.6 minutes of repeated setup work per job.

The issue's proposed GitHub Actions Cache integration is not a one-line cache
change. The `docker-container` driver cannot consume the locally loaded
`experimenter:megazords` build context, so the proposal also adds a temporary
registry, pushes `megazords` to it, and rewrites downstream build contexts.

## What this proof tests

The proof pins the issue-era source and expresses one representative test-job
graph as four Bake targets:

- `megazords`
- `schemas`
- `cirrus`
- `experimenter-test`

Bake's `target:megazords` context connects the dependent images without a
temporary registry. BoringCache discovers the selected targets and gives each
one an isolated cache automatically:

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
    --load \
    ci-test
```

## Result

Pending the isolated bootstrap and unchanged-source warm replay.

## Evidence

Pending public workflow runs and benchmark artifacts.

## What this would mean for Experimenter

This is a design-partner integration, not a drop-in replacement. The proof
tests the exact Dockerfiles and image dependency, but adopting it would mean
making Bake the owner of the build graph and then fitting that graph into the
existing composite action, retry behavior, Make targets, and Compose-based test
lifecycle.

The expected UX improvement is narrower and concrete: one cached Bake command
can replace the per-image cache flags and the temporary registry workaround,
while preserving the local image tags that later job steps use.
