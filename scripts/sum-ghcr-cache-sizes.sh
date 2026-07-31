#!/usr/bin/env bash
set -euo pipefail

package_owner="${1:?GHCR package owner is required}"
package_name="${2:?GHCR package name is required}"
registry_ref="${3:?GHCR repository reference is required}"
active_tag="${4:?active cache tag is required}"
breakdown_path="${GHCR_STORAGE_BREAKDOWN_PATH:-}"

case "$package_owner" in
  ''|*[!A-Za-z0-9_.-]*)
    echo "Invalid GHCR package owner: ${package_owner}" >&2
    exit 1
    ;;
esac

case "$package_name" in
  ''|*[!A-Za-z0-9_.-]*)
    echo "Invalid GHCR package name: ${package_name}" >&2
    exit 1
    ;;
esac

for tool in docker gh jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${tool} is required" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

versions_path="${work_dir}/versions.json"
manifests_path="${work_dir}/manifests.jsonl"
descriptors_path="${work_dir}/descriptors.jsonl"
manifest_files_path="${work_dir}/manifest-files.jsonl"
: > "$manifests_path"
: > "$descriptors_path"
: > "$manifest_files_path"

gh api --paginate \
  "/orgs/${package_owner}/packages/container/${package_name}/versions?per_page=100" \
  | jq -s 'add' > "$versions_path"

version_count="$(jq 'length' "$versions_path")"
if [[ "$version_count" -eq 0 ]]; then
  echo "No GHCR package versions found for ${package_owner}/${package_name}" >&2
  exit 1
fi

collect_manifest_tree() {
  local digest="$1"
  local depth="${2:-0}"
  if [[ "$depth" -gt 4 ]]; then
    echo "GHCR manifest nesting exceeded four levels at ${digest}" >&2
    return 1
  fi

  local manifest_path="${work_dir}/${digest#sha256:}.json"
  if [[ ! -f "$manifest_path" ]]; then
    docker buildx imagetools inspect --raw "${registry_ref}@${digest}" > "$manifest_path"
    local manifest_bytes
    manifest_bytes="$(wc -c < "$manifest_path" | tr -d ' ')"
    jq -n -c \
      --arg digest "$digest" \
      --argjson size "$manifest_bytes" \
      '{digest: $digest, size: $size}' >> "$manifest_files_path"
  fi

  local media_type
  media_type="$(jq -r '.mediaType // ""' "$manifest_path")"
  case "$media_type" in
    application/vnd.oci.image.manifest.v1+json|application/vnd.docker.distribution.manifest.v2+json)
      if ! jq -e '(.config | type == "object") and (.layers | type == "array")' "$manifest_path" >/dev/null; then
        echo "Invalid image manifest for ${registry_ref}@${digest}" >&2
        return 1
      fi
      jq -c '([.config] + .layers)[] | select(.digest and .size)' "$manifest_path" >> "$descriptors_path"
      jq '[.config.size, (.layers[]?.size)] | add // 0' "$manifest_path"
      ;;
    application/vnd.oci.image.index.v1+json|application/vnd.docker.distribution.manifest.list.v2+json)
      local logical_bytes=0
      local child_digest
      local child_bytes
      while IFS= read -r child_digest; do
        child_bytes="$(collect_manifest_tree "$child_digest" "$((depth + 1))")"
        logical_bytes="$((logical_bytes + child_bytes))"
      done < <(jq -r '.manifests[]?.digest' "$manifest_path")
      printf '%s\n' "$logical_bytes"
      ;;
    *)
      echo "Unsupported manifest media type '${media_type}' for ${registry_ref}@${digest}" >&2
      return 1
      ;;
  esac
}

while IFS= read -r version_json; do
  digest="$(jq -r '.name' <<< "$version_json")"
  if ! [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Unexpected GHCR package version digest: ${digest}" >&2
    exit 1
  fi

  logical_bytes="$(collect_manifest_tree "$digest")"
  manifest_path="${work_dir}/${digest#sha256:}.json"
  manifest_bytes="$(wc -c < "$manifest_path" | tr -d ' ')"
  media_type="$(jq -r '.mediaType // ""' "$manifest_path")"
  tags="$(jq -c '.metadata.container.tags // []' <<< "$version_json")"
  created_at="$(jq -r '.created_at // ""' <<< "$version_json")"
  updated_at="$(jq -r '.updated_at // ""' <<< "$version_json")"

  jq -n -c \
    --arg digest "$digest" \
    --arg created_at "$created_at" \
    --arg updated_at "$updated_at" \
    --arg media_type "$media_type" \
    --argjson tags "$tags" \
    --argjson manifest_bytes "$manifest_bytes" \
    --argjson logical_bytes "$logical_bytes" \
    '{
      digest: $digest,
      tags: $tags,
      created_at: $created_at,
      updated_at: $updated_at,
      media_type: $media_type,
      manifest_bytes: $manifest_bytes,
      logical_bytes: $logical_bytes
    }' >> "$manifests_path"
done < <(jq -c '.[]' "$versions_path")

unique_blob_bytes="$(jq -s 'unique_by(.digest) | map(.size) | add // 0' "$descriptors_path")"
manifest_bytes="$(jq -s 'unique_by(.digest) | map(.size) | add // 0' "$manifest_files_path")"
retained_bytes="$((unique_blob_bytes + manifest_bytes))"

active_count="$(jq -s --arg tag "$active_tag" 'map(select(.tags | index($tag))) | length' "$manifests_path")"
if [[ "$active_count" -ne 1 ]]; then
  echo "Expected one active GHCR manifest for tag ${active_tag}, found ${active_count}" >&2
  exit 1
fi

breakdown="$(
  jq -n \
    --arg registry_ref "$registry_ref" \
    --arg package_owner "$package_owner" \
    --arg package_name "$package_name" \
    --arg active_tag "$active_tag" \
    --argjson retained_bytes "$retained_bytes" \
    --argjson retained_unique_blob_bytes "$unique_blob_bytes" \
    --argjson retained_manifest_bytes "$manifest_bytes" \
    --slurpfile manifests "$manifests_path" \
    '{
      schema_version: "ghcr_cache_storage.v1",
      registry_ref: $registry_ref,
      package: {
        owner: $package_owner,
        name: $package_name
      },
      versions: {
        total: ($manifests | length),
        tagged: ($manifests | map(select(.tags | length > 0)) | length),
        untagged: ($manifests | map(select(.tags | length == 0)) | length)
      },
      active: (($manifests | map(select(.tags | index($active_tag))) | first) + {tag: $active_tag}),
      retained_bytes: $retained_bytes,
      retained_unique_blob_bytes: $retained_unique_blob_bytes,
      retained_manifest_bytes: $retained_manifest_bytes,
      manifests: $manifests
    }'
)"

if [[ -n "$breakdown_path" ]]; then
  mkdir -p "$(dirname "$breakdown_path")"
  printf '%s\n' "$breakdown" > "$breakdown_path"
fi

printf '%s\n' "$retained_bytes"
