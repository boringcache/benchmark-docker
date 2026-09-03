#!/usr/bin/env python3
"""Apply run-specific values to a committed Docker cache plan."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[1]
RUN_HINT_KEYS = {"benchmark", "case", "fidelity", "phase"}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--plan-directory", required=True)
    result.add_argument("--cache-scope", required=True)
    result.add_argument("--image-repository", required=True)
    result.add_argument("--image-tag", required=True)
    result.add_argument("--platform", default="")
    result.add_argument("--tool-cache", default="")
    result.add_argument("--mount-cache", action="store_true")
    result.add_argument("--no-cache", action="store_true")
    result.add_argument("--metadata-hint", action="append", default=[])
    return result


def replace_setting(body: str, key: str, value: str | None) -> str:
    lines = body.splitlines(keepends=True)
    start = next(
        (index for index, line in enumerate(lines) if line.startswith(f"{key} =")), None
    )
    if start is not None:
        end = start + 1
        if "[" in lines[start] and "]" not in lines[start]:
            while end < len(lines) and "]" not in lines[end - 1]:
                end += 1
        replacement = [] if value is None else [f"{key} = {value}\n"]
        lines[start:end] = replacement
        return "".join(lines)

    if value is None:
        return body
    command_index = next(
        (index for index, line in enumerate(lines) if line.startswith("command = [")),
        len(lines),
    )
    lines.insert(command_index, f"{key} = {value}\n")
    return "".join(lines)


def replace_command(body: str, command: list[str]) -> str:
    lines = body.splitlines(keepends=True)
    start = next(
        index for index, line in enumerate(lines) if line.startswith("command = [")
    )
    end = start + 1
    while end < len(lines) and lines[end].strip() != "]":
        end += 1
    if end == len(lines):
        raise ValueError("Docker command array is not closed")
    rendered = [
        "command = [\n",
        *(f"  {json.dumps(value)},\n" for value in command),
        "]\n",
    ]
    lines[start : end + 1] = rendered
    return "".join(lines)


def main() -> None:
    args = parser().parse_args()
    config_path = (ROOT / args.plan_directory / ".boringcache.toml").resolve()
    if ROOT not in config_path.parents:
        raise ValueError("Plan directory must stay inside the proof repository")

    text = config_path.read_text()
    parsed = tomllib.loads(text)
    adapter = parsed["adapters"]["docker"]
    command = list(adapter["command"])

    image_matches = [
        index
        for index, value in enumerate(command)
        if value.startswith(f"{args.image_repository}:")
    ]
    if len(image_matches) != 1:
        raise ValueError(
            f"Expected one {args.image_repository} image reference in the Docker command"
        )
    command[image_matches[0]] = f"{args.image_repository}:{args.image_tag}"
    platform_matches = [
        index for index, value in enumerate(command[:-1]) if value == "--platform"
    ]
    if len(platform_matches) > 1:
        raise ValueError("Expected at most one --platform in the Docker command")
    if args.platform:
        if platform_matches:
            command[platform_matches[0] + 1] = args.platform
        else:
            file_index = command.index("--file")
            command[file_index + 2 : file_index + 2] = ["--platform", args.platform]
    if args.no_cache and "--no-cache" not in command:
        command.insert(command.index("build") + 1, "--no-cache")

    section = re.search(
        r"(?ms)^\[adapters\.docker\]\n(?P<body>.*?)(?=^\[|\Z)",
        text,
    )
    if section is None:
        raise ValueError("Missing [adapters.docker] plan")

    hints = [
        hint
        for hint in adapter.get("metadata-hints", [])
        if hint.partition("=")[0] not in RUN_HINT_KEYS
    ]
    hints.extend(args.metadata_hint)

    body = section.group("body")
    body = replace_setting(body, "tag", json.dumps(args.cache_scope))
    body = replace_setting(body, "metadata-hints", json.dumps(hints))
    body = replace_setting(
        body,
        "tool-cache",
        json.dumps([args.tool_cache]) if args.tool_cache else None,
    )
    body = replace_setting(body, "mount-cache", "true" if args.mount_cache else None)
    body = replace_command(body, command)
    configured = text[: section.start("body")] + body + text[section.end("body") :]

    configured_adapter = tomllib.loads(configured)["adapters"]["docker"]
    if configured_adapter["tag"] != args.cache_scope:
        raise ValueError(
            "Configured Docker cache scope does not match the requested scope"
        )
    if configured_adapter["command"] != command:
        raise ValueError(
            "Configured Docker command does not match the requested command"
        )
    if configured_adapter["metadata-hints"] != hints:
        raise ValueError("Configured metadata hints do not match the requested hints")
    if configured_adapter.get("tool-cache", []) != (
        [args.tool_cache] if args.tool_cache else []
    ):
        raise ValueError(
            "Configured tool cache does not match the requested tool cache"
        )
    if configured_adapter.get("mount-cache", False) is not args.mount_cache:
        raise ValueError("Configured mount-cache setting does not match the request")
    config_path.write_text(configured)


if __name__ == "__main__":
    main()
