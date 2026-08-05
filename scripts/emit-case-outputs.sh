#!/usr/bin/env bash
set -euo pipefail

case_id="${1:?case id is required}"
ref_key="${2:?case ref key is required}"
build_output="${3:-none}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case_file="${repo_root}/cases/${case_id}.json"

[[ -f "$case_file" ]] || { echo "Unknown case: ${case_id}" >&2; exit 1; }
[[ "$(jq -r '.id' "$case_file")" == "$case_id" ]] || { echo "Case id mismatch: ${case_id}" >&2; exit 1; }

build_family="$(jq -r '.docker.build_family // "buildx-build"' "$case_file")"
[[ "$build_family" == "buildx-build" ]] || {
  echo "${case_id} uses ${build_family}; Bake, Compose, and Docker alias contracts are exercised in product E2E." >&2
  exit 1
}

project_ref="$("${repo_root}/scripts/resolve-case-ref.sh" "$case_file" "$ref_key")"
benchmark_ref="$ref_key"
[[ ! "$ref_key" =~ ^[0-9a-f]{40}$ ]] || benchmark_ref="${ref_key:0:12}"
project_repo="$(jq -er '.source.repo' "$case_file")"
cache_id="$(jq -r --arg fallback "$case_id" '.docker.cache_id // $fallback' "$case_file")"
dockerfile="$(jq -er '.docker.dockerfile' "$case_file")"
context="$(jq -r '.docker.context // "."' "$case_file")"
image="$(jq -er '.docker.image' "$case_file")"
source_path=".work/${case_id}/source"

case "$build_output" in
  none|load)
    image_repository="cache-proof/${image}"
    ;;
  ghcr)
    image_repository="ghcr.io/${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER is required}/${image}-proof"
    ;;
  *)
    echo "Unknown build output: ${build_output}" >&2
    exit 1
    ;;
esac

image_tag="${ref_key}-${GITHUB_RUN_ID:-local}"
build_args="$(jq -r --arg project_ref "$project_ref" '.docker.build_args[]? | gsub("\\{PROJECT_REF\\}"; $project_ref)' "$case_file")"
target="$(jq -r '.docker.target // ""' "$case_file")"
platforms="$(jq -r '.docker.platform // ""' "$case_file")"
docker_tool_cache="$(jq -r '.docker.tool_cache // ""' "$case_file")"
sbom="$(jq -r 'any(.docker.extra_args[]?; . == "--sbom=true")' "$case_file")"
provenance="$(jq -r 'any(.docker.extra_args[]?; startswith("--provenance=") and . != "--provenance=false")' "$case_file")"

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

write_multiline_output() {
  local delimiter
  delimiter="case_${1}_$(date +%s%N)"
  {
    echo "$1<<${delimiter}"
    printf '%s\n' "$2"
    echo "$delimiter"
  } >> "$GITHUB_OUTPUT"
}

write_output case_id "$case_id"
write_output case_ref_key "$ref_key"
write_output benchmark_id "${case_id}-${benchmark_ref}"
write_output cache_id "$cache_id"
write_output project_repo "$project_repo"
write_output project_ref "$project_ref"
write_output dockerfile_path "${source_path}/${dockerfile}"
write_output docker_context "${source_path}/${context}"
write_output image_repository "$image_repository"
write_output image_tag "$image_tag"
write_output target "$target"
write_output platforms "$platforms"
write_multiline_output build_args "$build_args"
write_multiline_output docker_tool_cache "$docker_tool_cache"
write_output sbom "$sbom"
write_output provenance "$provenance"
write_output cli_version "$(jq -r '.workflow.cli_version // ""' "$case_file")"
write_output runner_label "$(jq -r '.workflow.runner_label // "ubuntu-latest"' "$case_file")"
write_output cli_platform "$(jq -r '.workflow.cli_platform // "linux-amd64"' "$case_file")"
write_output free_disk_space "$(jq -r '.workflow.free_disk_space // false' "$case_file")"
write_output setup_qemu "$(jq -r '.workflow.setup_qemu // false' "$case_file")"
write_output rust_target_cache_kind "$(jq -r '.docker.rust_target_cache.kind // ""' "$case_file")"
write_output rust_target_cache_id_pattern "$(jq -r '.docker.rust_target_cache.id_pattern // ""' "$case_file")"
write_output native_matrix "$(jq -c '.workflow.native_matrix // {include: []}' "$case_file")"
write_output native_matrix_enabled "$(jq -r '((.workflow.native_matrix.include // []) | length) > 0' "$case_file")"
