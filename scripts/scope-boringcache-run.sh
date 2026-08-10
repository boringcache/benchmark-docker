#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scope="${1:-}"
plan_directory="${2:-}"

if [[ ! "$scope" =~ ^[a-z0-9][a-z0-9._-]+$ ]]; then
  echo "Expected a lowercase benchmark cache scope, got: ${scope:-<empty>}" >&2
  exit 1
fi

case "/${plan_directory}/" in
  *"/../"*) echo "Plan directory must stay inside the proof repository: ${plan_directory}" >&2; exit 1 ;;
esac
if [[ -z "$plan_directory" || "$plan_directory" == /* ]]; then
  echo "Expected a relative committed plan directory, got: ${plan_directory:-<empty>}" >&2
  exit 1
fi

config_path="${repo_root}/${plan_directory}/.boringcache.toml"
[[ -f "$config_path" ]] || {
  echo "Missing committed plan: ${config_path}" >&2
  exit 1
}
tag_lines="$(grep -c '^tag = "docker-cache-proof-' "$config_path")"
[[ "$tag_lines" == "1" ]] || {
  echo "Expected one Docker proof tag in ${config_path}" >&2
  exit 1
}
sed -i.bak -E "s/^tag = \"docker-cache-proof-[^\"]+\"$/tag = \"${scope}\"/" "$config_path"
rm -f "${config_path}.bak"
echo "Scoped the BoringCache Docker tag to ${scope}."
