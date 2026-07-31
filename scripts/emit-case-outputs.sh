#!/usr/bin/env bash
set -euo pipefail

case_id="${1:?case id is required}"
ref_key="${2:?case ref key is required}"
build_output="${3:-none}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case_file="${repo_root}/cases/${case_id}.json"

if [[ ! -f "$case_file" ]]; then
  echo "Unknown case: ${case_id}" >&2
  exit 1
fi

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
  fi
}

write_output() {
  local key="$1"
  local value="$2"
  echo "${key}=${value}" >> "$GITHUB_OUTPUT"
}

write_multiline_output() {
  local key="$1"
  local value="$2"
  local delimiter
  delimiter="case_${key}_$(date +%s%N)"
  {
    echo "${key}<<${delimiter}"
    printf '%s\n' "$value"
    echo "${delimiter}"
  } >> "$GITHUB_OUTPUT"
}

require_jq

manifest_id="$(jq -r '.id' "$case_file")"
if [[ "$manifest_id" != "$case_id" ]]; then
  echo "Case file id mismatch: expected ${case_id}, got ${manifest_id}" >&2
  exit 1
fi

project_ref="$("${repo_root}/scripts/resolve-case-ref.sh" "$case_file" "$ref_key")"
benchmark_ref="$ref_key"
if [[ "$ref_key" =~ ^[0-9a-f]{40}$ ]]; then
  benchmark_ref="${ref_key:0:12}"
fi
project_repo="$(jq -er '.source.repo' "$case_file")"
dockerfile="$(jq -er '.docker.dockerfile' "$case_file")"
context="$(jq -er '.docker.context' "$case_file")"
image="$(jq -er '.docker.image' "$case_file")"
runner_label="$(jq -r '.workflow.runner_label // "ubuntu-latest"' "$case_file")"
cli_platform="$(jq -r '.workflow.cli_platform // "linux-amd64"' "$case_file")"
free_disk_space="$(jq -r '.workflow.free_disk_space // false' "$case_file")"
setup_qemu="$(jq -r '.workflow.setup_qemu // false' "$case_file")"
docker_tool_cache="$(jq -r '.docker.tool_cache // ""' "$case_file")"
rust_target_cache_kind="$(jq -r '.docker.rust_target_cache.kind // ""' "$case_file")"
rust_target_cache_id_pattern="$(jq -r '.docker.rust_target_cache.id_pattern // ""' "$case_file")"
native_matrix="$(jq -c '.workflow.native_matrix // {include: []}' "$case_file")"
native_matrix_enabled="$(jq -r '((.workflow.native_matrix.include // []) | length) > 0' "$case_file")"
source_path=".work/${case_id}/source"
image_tag="cache-proof/${image}:${ref_key}-${GITHUB_RUN_ID:-local}"

if [[ "$build_output" == "local-registry" ]]; then
  image_tag="127.0.0.1:5001/${image}:${ref_key}-${GITHUB_RUN_ID:-local}"
fi

extra_args="$(
  {
    jq -r '.docker.extra_args[]?' "$case_file"
    jq -r --arg project_ref "$project_ref" '.docker.build_args[]? | gsub("\\{PROJECT_REF\\}"; $project_ref) | "--build-arg=" + .' "$case_file"
    target="$(jq -r '.docker.target // empty' "$case_file")"
    if [[ -n "$target" ]]; then
      printf '%s\n' "--target=${target}"
    fi
    platform="$(jq -r '.docker.platform // empty' "$case_file")"
    if [[ -n "$platform" ]]; then
      printf '%s\n' "--platform=${platform}"
    fi
  } | sed '/^$/d'
)"

write_output "case_id" "$case_id"
write_output "case_ref_key" "$ref_key"
write_output "benchmark_id" "${case_id}-${benchmark_ref}"
write_output "cache_id" "$case_id"
write_output "project_repo" "$project_repo"
write_output "project_ref" "$project_ref"
write_output "dockerfile_path" "${source_path}/${dockerfile}"
write_output "docker_context" "${source_path}/${context}"
write_output "image_tag" "$image_tag"
write_output "runner_label" "$runner_label"
write_output "cli_platform" "$cli_platform"
write_output "free_disk_space" "$free_disk_space"
write_output "setup_qemu" "$setup_qemu"
write_multiline_output "docker_tool_cache" "$docker_tool_cache"
write_output "rust_target_cache_kind" "$rust_target_cache_kind"
write_output "rust_target_cache_id_pattern" "$rust_target_cache_id_pattern"
write_output "native_matrix" "$native_matrix"
write_output "native_matrix_enabled" "$native_matrix_enabled"
write_multiline_output "docker_build_extra_args" "$extra_args"
