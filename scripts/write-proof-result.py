#!/usr/bin/env python3
"""Write a safe, standalone result for one Docker proof phase."""

import json
import os
import time
from pathlib import Path


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"{name} is required for the Docker proof result")
    return value


def main() -> int:
    evidence = json.loads(Path(required("EVIDENCE_PATH")).read_text())
    restore = (evidence.get("phases") or {}).get("restore") or {}
    plan = ((restore.get("mode_evidence") or {}).get("buildkit_cache") or {})
    source_sha = required("SOURCE_SHA")
    if len(source_sha) != 40 or any(character not in "0123456789abcdef" for character in source_sha):
        raise SystemExit("SOURCE_SHA must be the exact 40-character source commit")

    result = {
        "schema_version": 1,
        "case": required("CASE_ID"),
        "lane": required("CACHE_LANE"),
        "phase": required("PHASE"),
        "source": {
            "repository": required("SOURCE_REPOSITORY"),
            "sha": source_sha,
        },
        "timing": {
            "phase_seconds": int(time.time()) - int(required("BUILD_STARTED_AT")),
        },
        "cache": {
            "workspace": restore.get("workspace"),
            "tag": restore.get("cache_tag") or required("CACHE_SCOPE"),
            "hit": restore.get("cache_hit"),
            "result": restore.get("cache_result"),
            "planned_import_tags": plan.get("cache_from_tags") or [],
            "planned_import_refs": len(plan.get("cache_from_refs") or []),
            "export_tag": plan.get("cache_to_tag"),
        },
        "product_refs": evidence.get("product_refs") or {},
        "github": {
            "repository": os.environ.get("GITHUB_REPOSITORY"),
            "run_id": os.environ.get("GITHUB_RUN_ID"),
            "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
            "job": os.environ.get("GITHUB_JOB"),
            "runner_os": os.environ.get("RUNNER_OS"),
            "runner_arch": os.environ.get("RUNNER_ARCH"),
            "runner_name": os.environ.get("RUNNER_NAME"),
            "runner_image": os.environ.get("ImageOS"),
            "runner_image_version": os.environ.get("ImageVersion"),
        },
    }
    output = Path("benchmark-results") / f"{result['case']}-{result['phase']}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
