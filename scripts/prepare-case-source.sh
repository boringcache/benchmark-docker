#!/usr/bin/env bash
set -euo pipefail

case_id="${1:?case id is required}"
ref_key="${2:?case ref key is required}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case_file="${repo_root}/cases/${case_id}.json"

if [[ ! -f "$case_file" ]]; then
  echo "Unknown case: ${case_id}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

project_repo="$(jq -er '.source.repo' "$case_file")"
project_ref="$("${repo_root}/scripts/resolve-case-ref.sh" "$case_file" "$ref_key")"
fetch_depth="$(jq -r '.source.fetch_depth // 1' "$case_file")"
project_tag="$(jq -r --arg key "$ref_key" '.ref_metadata[$key].tag // ""' "$case_file")"
project_l10n_sha="$(jq -r --arg key "$ref_key" '.ref_metadata[$key].l10n_sha // ""' "$case_file")"
overlay_dockerfile="$(jq -r '.docker.overlay_dockerfile // ""' "$case_file")"
source_dir="${repo_root}/.work/${case_id}/source"
clone_url="https://github.com/${project_repo}.git"

rm -rf "${repo_root}/.work/${case_id}"
mkdir -p "$source_dir"
git init "$source_dir"
git -C "$source_dir" remote add origin "$clone_url"
case "$fetch_depth" in
  0|full)
    git -C "$source_dir" -c protocol.version=2 fetch --tags origin "$project_ref"
    ;;
  ''|*[!0-9]*)
    echo "Invalid source.fetch_depth for ${case_id}: ${fetch_depth}" >&2
    exit 1
    ;;
  *)
    git -C "$source_dir" -c protocol.version=2 fetch --depth="$fetch_depth" origin "$project_ref"
    ;;
esac
git -C "$source_dir" checkout --detach FETCH_HEAD

actual_ref="$(git -C "$source_dir" rev-parse HEAD)"
if [[ "$actual_ref" != "$project_ref" ]]; then
  echo "Prepared ${actual_ref}, expected ${project_ref}" >&2
  exit 1
fi

prepare_step=0
while IFS= read -r prepare_command; do
  [[ -n "$prepare_command" ]] || continue
  prepare_step=$((prepare_step + 1))
  echo "Preparing ${case_id} source (step ${prepare_step})"
  (
    cd "$source_dir"
    PROOF_REPO_ROOT="$repo_root" \
      CASE_ID="$case_id" \
      PROJECT_REF="$actual_ref" \
      PROJECT_TAG="$project_tag" \
      PROJECT_L10N_SHA="$project_l10n_sha" \
      bash -euo pipefail -c "$prepare_command"
  )
done < <(jq -r '.docker.prepare_commands[]?' "$case_file")

if [[ -n "$overlay_dockerfile" ]]; then
  dockerfile_path="$(jq -er '.docker.dockerfile' "$case_file")"
  overlay_source="${repo_root}/${overlay_dockerfile}"
  overlay_target="${source_dir}/${dockerfile_path}"
  if [[ ! -f "$overlay_source" ]]; then
    echo "Missing Dockerfile overlay: ${overlay_source}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$overlay_target")"
  cp "$overlay_source" "$overlay_target"
fi

while IFS=$'\t' read -r overlay_source_path overlay_target_path; do
  [[ -n "$overlay_source_path" && -n "$overlay_target_path" ]] || continue
  case "/${overlay_source_path}/" in
    *"/../"*) echo "Overlay source must stay inside the proof repository: ${overlay_source_path}" >&2; exit 1 ;;
  esac
  case "/${overlay_target_path}/" in
    *"/../"*) echo "Overlay target must stay inside the prepared source: ${overlay_target_path}" >&2; exit 1 ;;
  esac
  if [[ "$overlay_source_path" == /* || "$overlay_target_path" == /* ]]; then
    echo "Overlay paths must be relative: ${overlay_source_path} -> ${overlay_target_path}" >&2
    exit 1
  fi

  overlay_source="${repo_root}/${overlay_source_path}"
  overlay_target="${source_dir}/${overlay_target_path}"
  if [[ ! -f "$overlay_source" ]]; then
    echo "Missing overlay file: ${overlay_source}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$overlay_target")"
  cp "$overlay_source" "$overlay_target"
done < <(jq -r '.docker.overlay_files[]? | [.source, .target] | @tsv' "$case_file")

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "source_path=.work/${case_id}/source"
    echo "project_ref=${actual_ref}"
  } >> "$GITHUB_OUTPUT"
fi
