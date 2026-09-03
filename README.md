# BoringCache Docker benchmark

This repository contains 47 pinned real-world Docker workloads.

Each case and every allowed source ref has an executable `.boringcache.toml`
under [`plans/`](plans/). The workflow selects one committed plan; Action inputs
are projected from that plan rather than reconstructing the Docker command.
Case JSON now owns only source checkout, upstream workflow/evidence anchors,
prerequisites, runner selection, and explicit product experiments.
[`FIDELITY.md`](FIDELITY.md) distinguishes direct upstream steps, individual
matrix members, wrapper projections, and deliberate diagnostic variants.

Run `python3 scripts/verify-upstream-recipe.py` from a Python 3.11+ environment
to check all 47 cases and 221 case/ref plans. A benchmark also checks that the
selected pinned source still contains its recorded upstream Docker workflow.
