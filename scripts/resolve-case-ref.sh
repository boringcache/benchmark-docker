#!/usr/bin/env bash
set -euo pipefail

case_file="${1:?case file is required}"
ref="${2:?case ref is required}"

resolved_ref="$(jq -r --arg key "$ref" '.refs[$key] // empty' "$case_file")"
if [[ ! "$resolved_ref" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Unknown or invalid case ref: ${ref}" >&2
  exit 1
fi

printf '%s\n' "$resolved_ref"
