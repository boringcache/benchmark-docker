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
cache_id="$(jq -r --arg fallback "$case_id" '.docker.cache_id // $fallback' "$case_file")"
build_family="$(jq -r '.docker.build_family // "buildx-build"' "$case_file")"
dockerfile="$(jq -r '.docker.dockerfile // ""' "$case_file")"
context="$(jq -r '.docker.context // "."' "$case_file")"
image="$(jq -er '.docker.image' "$case_file")"
bake_file="$(jq -r '.docker.bake_file // ""' "$case_file")"
bake_group="$(jq -r '.docker.bake_group // ""' "$case_file")"
compose_file="$(jq -r '.docker.compose_file // ""' "$case_file")"
compose_command="$(jq -r '.docker.compose_command[]?' "$case_file")"
compose_prepare_command="$(jq -r '.docker.compose_prepare_command // ""' "$case_file")"
compose_host_user="$(jq -r '.docker.compose_host_user // false' "$case_file")"
compose_success_service="$(jq -r '.docker.compose_success_service // ""' "$case_file")"
expected_images="$(jq -r '.docker.expected_images[]?' "$case_file")"
runner_label="$(jq -r '.workflow.runner_label // "ubuntu-latest"' "$case_file")"
cli_platform="$(jq -r '.workflow.cli_platform // "linux-amd64"' "$case_file")"
free_disk_space="$(jq -r '.workflow.free_disk_space // false' "$case_file")"
prune_builder="$(jq -r '.workflow.prune_builder // false' "$case_file")"
setup_qemu="$(jq -r '.workflow.setup_qemu // false' "$case_file")"
docker_tool_cache="$(jq -r '.docker.tool_cache // ""' "$case_file")"
rust_target_cache_kind="$(jq -r '.docker.rust_target_cache.kind // ""' "$case_file")"
rust_target_cache_id_pattern="$(jq -r '.docker.rust_target_cache.id_pattern // ""' "$case_file")"
native_matrix="$(jq -c '.workflow.native_matrix // {include: []}' "$case_file")"
native_matrix_enabled="$(jq -r '((.workflow.native_matrix.include // []) | length) > 0' "$case_file")"
source_path=".work/${case_id}/source"
image_tag="cache-proof/${image}:${ref_key}-${GITHUB_RUN_ID:-local}"

case "$build_family" in
  buildx-build|classic-build)
    if [[ -z "$dockerfile" ]]; then
      echo "docker.dockerfile is required for ${build_family} case ${case_id}" >&2
      exit 1
    fi
    if [[ "$build_family" == "classic-build" && "$build_output" != "load" ]]; then
      echo "classic-build case ${case_id} requires build_output=load to preserve the upstream local-image contract" >&2
      exit 1
    fi
    ;;
  bake)
    if [[ -z "$bake_file" || -z "$bake_group" ]]; then
      echo "docker.bake_file and docker.bake_group are required for Bake case ${case_id}" >&2
      exit 1
    fi
    ;;
  compose)
    if [[ -z "$compose_file" || -z "$compose_command" ]]; then
      echo "docker.compose_file and docker.compose_command are required for Compose case ${case_id}" >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported docker.build_family for ${case_id}: ${build_family}" >&2
    exit 1
    ;;
esac

if [[ "$build_output" == "local-registry" ]]; then
  image_tag="127.0.0.1:5001/${image}:${ref_key}-${GITHUB_RUN_ID:-local}"
elif [[ "$build_output" == "ghcr" ]]; then
  repository_owner="${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER is required for GHCR output}"
  image_tag="ghcr.io/${repository_owner}/${image}-proof:${ref_key}-${GITHUB_RUN_ID:-local}"
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
write_output "cache_id" "$cache_id"
write_output "project_repo" "$project_repo"
write_output "project_ref" "$project_ref"
write_output "docker_build_family" "$build_family"
write_output "docker_working_directory" "$source_path"
write_output "dockerfile_path" "${dockerfile:+${source_path}/${dockerfile}}"
write_output "docker_context" "${source_path}/${context}"
write_output "docker_bake_file" "$bake_file"
write_output "docker_bake_group" "$bake_group"
write_output "docker_compose_file" "$compose_file"
write_multiline_output "docker_compose_command" "$compose_command"
write_multiline_output "docker_compose_prepare_command" "$compose_prepare_command"
write_output "docker_compose_host_user" "$compose_host_user"
write_output "docker_compose_success_service" "$compose_success_service"
write_multiline_output "docker_expected_images" "$expected_images"
write_output "image_tag" "$image_tag"
write_output "runner_label" "$runner_label"
write_output "cli_platform" "$cli_platform"
write_output "free_disk_space" "$free_disk_space"
write_output "prune_builder" "$prune_builder"
write_output "setup_qemu" "$setup_qemu"
write_multiline_output "docker_tool_cache" "$docker_tool_cache"
write_output "rust_target_cache_kind" "$rust_target_cache_kind"
write_output "rust_target_cache_id_pattern" "$rust_target_cache_id_pattern"
write_output "native_matrix" "$native_matrix"
write_output "native_matrix_enabled" "$native_matrix_enabled"
write_multiline_output "docker_build_extra_args" "$extra_args"
