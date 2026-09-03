#!/usr/bin/env python3
"""Project one committed case/ref Docker plan into Action inputs."""

from __future__ import annotations

import json
import os
import re
import sys
import time
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def value_after(command: list[str], flag: str, default: str = "") -> str:
    try:
        return command[command.index(flag) + 1]
    except ValueError:
        return default


def values_after(command: list[str], flag: str) -> list[str]:
    return [command[index + 1] for index, value in enumerate(command[:-1]) if value == flag]


def write_output(name: str, value: str) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        print(f"{name}={value}")
        return
    if "\n" in value:
        delimiter = f"case_{name}_{time.time_ns()}"
        with open(output_path, "a") as output:
            output.write(f"{name}<<{delimiter}\n{value}\n{delimiter}\n")
    else:
        with open(output_path, "a") as output:
            output.write(f"{name}={value}\n")


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: emit-case-outputs.py CASE REF_KEY")
    case_id, ref_key = sys.argv[1:]
    case_path = ROOT / "cases" / f"{case_id}.json"
    case = json.loads(case_path.read_text())
    if case["id"] != case_id:
        raise SystemExit(f"Case id mismatch: {case_id}")
    if ref_key not in case["refs"]:
        raise SystemExit(f"Unknown committed ref plan for {case_id}: {ref_key}")

    plan_directory = Path("plans") / case_id / "refs" / ref_key
    with (ROOT / plan_directory / ".boringcache.toml").open("rb") as config_file:
        command = tomllib.load(config_file)["adapters"]["docker"]["command"]
    if command[:3] != ["docker", "buildx", "build"]:
        raise SystemExit(f"{plan_directory} is not a Docker Buildx plan")

    project_ref = case["refs"][ref_key]
    image_spec = value_after(command, "--tag")
    _, _, plan_tag = image_spec.rpartition(":")
    image = case["docker"]["image"]
    build_output = "ghcr" if "--push" in command else "load" if "--load" in command else "none"
    if build_output != case["docker"]["output"]:
        raise SystemExit(f"{case_id}/{ref_key} output does not match its committed case contract")
    if build_output == "ghcr":
        owner = os.environ.get("GITHUB_REPOSITORY_OWNER")
        if not owner:
            raise SystemExit("GITHUB_REPOSITORY_OWNER is required for ghcr output")
        image_repository = f"ghcr.io/{owner}/{image}-proof"
    else:
        image_repository = f"cache-proof/{image}"

    cache_id = case.get("docker", {}).get("cache_id", case_id)
    benchmark_ref = ref_key if not re.fullmatch(r"[0-9a-f]{40}", ref_key) else ref_key[:12]
    docker_tool_cache = case["docker"].get("tool_cache", "")
    workflow = case.get("workflow", {})
    native_matrix = workflow.get("native_matrix", {"include": []})

    outputs = {
        "case_id": case_id,
        "case_ref_key": ref_key,
        "plan_directory": str(plan_directory),
        "benchmark_id": f"{case_id}-{benchmark_ref}",
        "cache_id": cache_id,
        "fidelity_level": case["fidelity"]["level"],
        "project_repo": case["source"]["repo"],
        "project_ref": project_ref,
        "dockerfile_path": value_after(command, "--file"),
        "docker_context": command[-1],
        "image_repository": image_repository,
        "image_tag": f"{plan_tag}-{os.environ.get('GITHUB_RUN_ID', 'local')}",
        "build_output": build_output,
        "target": value_after(command, "--target"),
        "platforms": value_after(command, "--platform"),
        "build_args": "\n".join(values_after(command, "--build-arg")),
        "docker_tool_cache": docker_tool_cache,
        "sbom": str("--sbom=true" in command).lower(),
        "provenance": str(any(value.startswith("--provenance=") and value != "--provenance=false" for value in command)).lower(),
        "cli_version": workflow.get("cli_version", ""),
        "runner_label": workflow.get("runner_label", "ubuntu-latest"),
        "cli_platform": workflow.get("cli_platform", "linux-amd64"),
        "free_disk_space": str(workflow.get("free_disk_space", False)).lower(),
        "setup_qemu": str(workflow.get("setup_qemu", False)).lower(),
        "rust_target_cache_kind": case["docker"].get("rust_target_cache", {}).get("kind", ""),
        "rust_target_cache_id_pattern": case["docker"].get("rust_target_cache", {}).get("id_pattern", ""),
        "native_matrix": json.dumps(native_matrix, separators=(",", ":")),
        "native_matrix_enabled": str(bool(native_matrix.get("include"))).lower(),
    }
    for name, value in outputs.items():
        write_output(name, str(value))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
