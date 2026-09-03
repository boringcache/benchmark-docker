# BoringCache Docker benchmark

This repository contains 47 pinned real-world Docker workloads.

Each case and every allowed source ref has an executable `.boringcache.toml`
under [`plans/`](plans/). The workflow selects one committed plan and applies
only run-specific cache scope, image, platform, and experiment values to it.
BoringCache One receives the thin GitHub lifecycle inputs; the CLI consumes the
final plan and owns the Docker build. Workflow prerequisites such as QEMU stay
in their dedicated setup actions. Case JSON owns source checkout, upstream
workflow/evidence anchors, prerequisites, runner selection, and explicit
product experiments.
[`FIDELITY.md`](FIDELITY.md) distinguishes direct upstream steps, individual
matrix members, wrapper projections, and deliberate diagnostic variants.

Run `python3 scripts/verify-upstream-recipe.py` from a Python 3.11+ environment
to check all 47 cases and 221 case/ref plans. A benchmark also checks that the
selected pinned source still contains its recorded upstream Docker workflow.
