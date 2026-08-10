#!/usr/bin/env python3
"""Verify the Docker proof catalog, committed plans, and Action projection."""

from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIDELITY_LEVELS = {
    "direct-step",
    "matrix-member",
    "wrapper-projection",
    "diagnostic-tool-cache",
    "diagnostic-overlay",
}


class RecipeMismatch(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RecipeMismatch(message)


def expected_command(case: dict, ref_key: str, source_prefix: str) -> list[str]:
    docker = case["docker"]
    source = f"{source_prefix}.work/{case['id']}/source"
    command = ["docker", "buildx", "build", "--file", f"{source}/{docker['dockerfile']}"]
    if platform := docker.get("platform"):
        command.extend(("--platform", platform))
    if target := docker.get("target"):
        command.extend(("--target", target))
    source_sha = case["refs"][ref_key]
    for build_arg in docker.get("build_args", []):
        command.extend(("--build-arg", build_arg.replace("{PROJECT_REF}", source_sha)))
    command.extend(docker.get("extra_args", []))
    if docker["output"] == "ghcr":
        command.append("--push")
    elif docker["output"] == "load":
        command.append("--load")
    require(docker["output"] in ("none", "load", "ghcr"), f"{case['id']} has an invalid output contract")
    image = (
        f"ghcr.io/boringcache/{docker['image']}-proof"
        if docker["output"] == "ghcr"
        else f"cache-proof/{docker['image']}"
    )
    command.extend(
        (
            "--tag",
            f"{image}:{ref_key}",
            f"{source}/{docker.get('context', '.')}",
        )
    )
    return command


def load_command(path: Path) -> tuple[dict, list[str]]:
    with path.open("rb") as config_file:
        adapter = tomllib.load(config_file)["adapters"]["docker"]
    return adapter, adapter["command"]


def verify_catalog() -> int:
    cases = [json.loads(path.read_text()) for path in sorted((ROOT / "cases").glob("*.json"))]
    require(len(cases) == 47, f"expected 47 Docker cases, found {len(cases)}")
    case_ids = [case["id"] for case in cases]
    require(len(case_ids) == len(set(case_ids)), "case ids must be unique")

    default_case = next(case for case in cases if case["id"] == "anythingllm-primary")
    root_adapter, root_command = load_command(ROOT / ".boringcache.toml")
    require(root_command == expected_command(default_case, "main", ""), "root Docker plan drifted from its documented default case")
    require(root_adapter["tag"] == "docker-cache-proof-anythingllm-primary", "root cache identity drifted")

    for case in cases:
        case_id = case["id"]
        require(case["source"].get("workflow", "").startswith(".github/workflows/"), f"{case_id} has no upstream workflow anchor")
        require(case.get("fidelity", {}).get("level") in FIDELITY_LEVELS, f"{case_id} has no explicit fidelity classification")
        require(case["source"].get("evidence_run") or case["source"].get("pain_url"), f"{case_id} has no upstream evidence")
        require(case["refs"].get("main", "").isalnum() and len(case["refs"]["main"]) == 40, f"{case_id} has no pinned main SHA")
        require(case["docker"].get("build_family", "buildx-build") == "buildx-build", f"{case_id} is not a Buildx-build case")
        require(case["docker"].get("output") in ("none", "load", "ghcr"), f"{case_id} has no upstream output contract")

        default_path = ROOT / "plans" / case_id / ".boringcache.toml"
        default_adapter, default_command = load_command(default_path)
        require(default_command == expected_command(case, "main", "../../"), f"{case_id} default plan drifted")
        require(default_adapter["tag"] == f"docker-cache-proof-{case_id}", f"{case_id} cache identity drifted")

        for ref_key in case["refs"]:
            path = ROOT / "plans" / case_id / "refs" / ref_key / ".boringcache.toml"
            adapter, command = load_command(path)
            require(command == expected_command(case, ref_key, "../../../../"), f"{case_id}/{ref_key} plan drifted")
            require(adapter["tag"] == f"docker-cache-proof-{case_id}", f"{case_id}/{ref_key} cache identity drifted")
            require(adapter["no-platform"] is True and adapter["no-git"] is True, f"{case_id}/{ref_key} must use an explicit cohort")

    workflow = (ROOT / ".github/workflows/docker-cache-proofs.yml").read_text()
    try:
        case_input = workflow.split("      case_id:", 1)[1].split("      ref_key:", 1)[0]
    except IndexError as error:
        raise RecipeMismatch("could not read case_id workflow choices") from error
    options = [line.removeprefix("          - ") for line in case_input.splitlines() if line.startswith("          - ")]
    require(options == sorted(case_ids), "workflow choices and committed cases differ")
    require("python3 ./scripts/verify-upstream-recipe.py" in workflow, "workflow does not verify the catalog")
    require("plan_directory: ${{ steps.case.outputs.plan_directory }}" in workflow, "workflow does not expose the selected plan")

    action = (ROOT / ".github/actions/docker-product-proof/action.yml").read_text()
    require("uses: actions/setup-python@v6" in action, "case runners do not provide Python 3.11+")
    require(action.count("working-directory: ${{ inputs.plan_directory }}") == 2, "both trust paths must consume the selected plan")
    require('scope-boringcache-run.sh "$cache_scope" "$PLAN_DIRECTORY"' in action, "cache cohort does not target the selected plan")
    emit = (ROOT / "scripts/emit-case-outputs.sh").read_text()
    require("emit-case-outputs.py" in emit and "jq" not in emit, "Action inputs must project from TOML")
    return len(cases)


def verify_prepared(case_id: str, source: Path) -> None:
    case = json.loads((ROOT / "cases" / f"{case_id}.json").read_text())
    workflow = source / case["source"]["workflow"]
    require(workflow.is_file(), f"{case_id} pinned source has no {case['source']['workflow']}")
    anchor = case["source"].get("anchor", "docker")
    require(
        anchor.lower() in workflow.read_text().lower(),
        f"{case_id} upstream workflow no longer contains its {anchor!r} phase",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case")
    parser.add_argument("--source", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        count = verify_catalog()
        if args.case or args.source:
            require(bool(args.case and args.source), "--case and --source must be passed together")
            verify_prepared(args.case, args.source.resolve())
    except (KeyError, OSError, RecipeMismatch, json.JSONDecodeError, tomllib.TOMLDecodeError) as error:
        print(f"Docker recipe mismatch: {error}", file=sys.stderr)
        return 1
    print(f"Verified {count} Docker cases and every committed case/ref plan.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
