#!/usr/bin/env bash
set -euo pipefail

proxy_port=22243
proxy_log="${BORINGCACHE_PROXY_LOG_PATH:-/tmp/boringcache-proxy-${proxy_port}.log}"
build_log="$(mktemp /tmp/boringcache-build.XXXXXX)"
status_snapshot_path="$(mktemp /tmp/boringcache-status.XXXXXX)"
max_attempts=1
cache_export_pattern='expected sha256:.*got sha256:e3b0|error writing layer blob|400 Bad Request|broken pipe'
mode="${1:-rolling}"
cache_import_ready="${BORINGCACHE_CACHE_IMPORT_READY:-true}"
cache_requested_from_refs="${BORINGCACHE_CACHE_REQUESTED_FROM_REFS:-}"
cache_used_from_refs="${BORINGCACHE_CACHE_USED_FROM_REFS:-}"
cache_unreadable_from_refs="${BORINGCACHE_CACHE_UNREADABLE_FROM_REFS:-}"
cache_promotion_refs="${BORINGCACHE_DOCKER_PROMOTION_REFS:-}"
allow_rolling_bootstrap="${ALLOW_BORINGCACHE_ROLLING_BOOTSTRAP:-false}"
build_output="${BENCHMARK_BUILD_OUTPUT:-none}"
docker_tool_cache="${DOCKER_TOOL_CACHE:-}"
docker_build_family="${DOCKER_BUILD_FAMILY:-buildx-build}"
docker_working_directory="${BENCHMARK_DOCKER_WORKING_DIRECTORY:-}"
docker_bake_file="${DOCKER_BAKE_FILE:-}"
docker_bake_group="${DOCKER_BAKE_GROUP:-}"
docker_compose_file="${DOCKER_COMPOSE_FILE:-}"
docker_compose_command="${DOCKER_COMPOSE_COMMAND:-}"
resolved_cache_tags_csv=""
export BORINGCACHE_OBSERVABILITY_INCLUDE_CACHE_OPS="${BORINGCACHE_OBSERVABILITY_INCLUDE_CACHE_OPS:-1}"
cleanup() { :; }
trap cleanup EXIT

find_step_id() {
  local pattern="$1"
  sed -nE "s/^#([0-9]+) ${pattern}.*/\\1/p" "$build_log" | tail -n1
}

find_step_seconds() {
  local step_id="$1"
  [[ -n "$step_id" ]] || return 0
  sed -nE "s/^#${step_id} DONE ([0-9]+(\\.[0-9]+)?)s$/\\1/p" "$build_log" | tail -n1
}

find_max_step_seconds() {
  local pattern="$1"
  local seconds=""
  local step_id=""

  while IFS= read -r step_id; do
    [[ -n "$step_id" ]] || continue
    seconds="$(find_step_seconds "$step_id")"
    [[ -n "$seconds" ]] && printf '%s\n' "$seconds"
  done < <(sed -nE "s/^#([0-9]+)( \\[[^]]+\\])? ${pattern}.*/\\1/p" "$build_log" | sort -u) \
    | sort -nr \
    | head -n1
}

write_build_metrics() {
  local output_path="${BENCHMARK_METRICS_OUTPUT:-}"
  [[ -n "$output_path" ]] || return 0

  local import_step=""
  local export_step=""
  local import_seconds=""
  local export_seconds=""
  local import_status=""
  local cached_steps=""

  if [[ "$docker_build_family" == "bake" || "$docker_build_family" == "compose" ]]; then
    import_seconds="$(find_max_step_seconds "importing cache manifest from")"
    export_seconds="$(find_max_step_seconds "exporting cache to boringcache")"
  else
    import_step="$(find_step_id "importing cache manifest from")"
    export_step="$(find_step_id "exporting cache to boringcache")"
    import_seconds="$(find_step_seconds "$import_step")"
    export_seconds="$(find_step_seconds "$export_step")"
  fi
  import_status="$(build_import_status)"
  cached_steps="$(grep -Ec '^#[0-9]+( \[[^]]+\])? CACHED$' "$build_log" || true)"

  mkdir -p "$(dirname "$output_path")"
  : > "$output_path"
  echo "cache_import_status=$import_status" >> "$output_path"
  echo "buildkit_cached_steps=$cached_steps" >> "$output_path"
  if [[ -n "$resolved_cache_tags_csv" ]]; then
    echo "resolved_cache_tags_csv=$resolved_cache_tags_csv" >> "$output_path"
  fi
  if [[ -n "$import_seconds" ]]; then
    echo "docker_cache_import_seconds=$import_seconds" >> "$output_path"
  fi
  if [[ -n "$export_seconds" ]]; then
    echo "docker_cache_export_seconds=$export_seconds" >> "$output_path"
  fi
  if [[ -n "${BORINGCACHE_BLOB_DOWNLOAD_CONCURRENCY:-}" ]]; then
    echo "blob_download_concurrency_override=${BORINGCACHE_BLOB_DOWNLOAD_CONCURRENCY}" >> "$output_path"
  fi
  if [[ -n "${BORINGCACHE_BLOB_PREFETCH_CONCURRENCY:-}" ]]; then
    echo "blob_prefetch_concurrency_override=${BORINGCACHE_BLOB_PREFETCH_CONCURRENCY}" >> "$output_path"
  fi
  if [[ -n "${BORINGCACHE_OCI_STREAM_THROUGH_MIN_BYTES:-}" ]]; then
    echo "oci_stream_through_min_bytes=${BORINGCACHE_OCI_STREAM_THROUGH_MIN_BYTES}" >> "$output_path"
  fi
  if [[ -s "$status_snapshot_path" ]] && command -v jq >/dev/null 2>&1; then
    append_status_metric() {
      local key="$1"
      local jq_expr="$2"
      local value=""
      value="$(jq -r "$jq_expr // empty" "$status_snapshot_path" 2>/dev/null || true)"
      if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$key=$value" >> "$output_path"
      fi
    }

    append_status_metric oci_hydration_policy '.startup_prefetch.startup_prefetch_oci_hydration'
    append_status_metric startup_oci_body_inserted '.startup_prefetch.startup_prefetch_oci_body_inserted'
    append_status_metric startup_oci_body_failures '.startup_prefetch.startup_prefetch_oci_body_failures'
    append_status_metric startup_oci_body_cold_blobs '.startup_prefetch.startup_prefetch_oci_body_cold_blobs'
    append_status_metric startup_oci_body_duration_ms '.startup_prefetch.startup_prefetch_oci_body_duration_ms'
    append_status_metric oci_body_local_hits '.oci_body.oci_body_local_hits'
    append_status_metric oci_body_remote_fetches '.oci_body.oci_body_remote_fetches'
    append_status_metric oci_body_local_bytes '.oci_body.oci_body_local_bytes'
    append_status_metric oci_body_remote_bytes '.oci_body.oci_body_remote_bytes'
    append_status_metric oci_body_local_duration_ms '.oci_body.oci_body_local_duration_ms'
    append_status_metric oci_body_remote_duration_ms '.oci_body.oci_body_remote_duration_ms'
    append_status_metric proxy_blob_download_max_concurrency '.session_summary.proxy.blob_download_max_concurrency'
    append_status_metric proxy_blob_prefetch_max_concurrency '.session_summary.proxy.blob_prefetch_max_concurrency'
    append_status_metric proxy_blob_prefetch_concurrency_source '.session_summary.proxy.blob_prefetch_concurrency_source'
    append_status_metric oci_stream_through_count '.oci_engine.oci_engine_stream_through_count'
    append_status_metric oci_stream_through_bytes '.oci_engine.oci_engine_stream_through_bytes'
    append_status_metric oci_stream_through_verify_duration_ms '.oci_engine.oci_engine_stream_through_verify_duration_ms'
    append_status_metric oci_stream_through_verify_failures '.oci_engine.oci_engine_stream_through_verify_failures'
    append_status_metric oci_stream_through_cache_promotion_failures '.oci_engine.oci_engine_stream_through_cache_promotion_failures'
  fi

  local observability_path="${BORINGCACHE_OBSERVABILITY_JSONL_PATH:-}"
  if [[ -n "$observability_path" && -s "$observability_path" ]] && command -v jq >/dev/null 2>&1; then
    detail_value() {
      local details="$1"
      local name="$2"
      printf '%s\n' "$details" | tr ' ' '\n' | awk -F= -v key="$name" '$1 == key { print $2; exit }'
    }
    append_metric() {
      local key="$1"
      local value="$2"
      if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$key=$value" >> "$output_path"
      fi
    }

    local plan_details=""
    plan_details="$(jq -r 'select(.operation == "oci_blob_upload_plan") | .details // empty' "$observability_path" 2>/dev/null | tail -n1 || true)"
    if [[ -n "$plan_details" ]]; then
      append_metric oci_upload_requested_blobs "$(detail_value "$plan_details" requested_blobs)"
      append_metric oci_new_blob_count "$(detail_value "$plan_details" upload_urls)"
      append_metric oci_upload_already_present "$(detail_value "$plan_details" already_present)"
    else
      append_metric oci_new_blob_count "0"
    fi

    local uploaded_blob_bytes=""
    uploaded_blob_bytes="$(jq -s -r '
      ([range(0; length) as $i | select(.[$i].operation == "oci_blob_upload_plan") | $i] | last) as $plan
      | if $plan == null then
          0
        else
          ([range(($plan + 1); length) as $i | .[$i] | select(.operation == "oci_blob_upload") | (.request_bytes // 0)] | add // 0)
        end
    ' "$observability_path" 2>/dev/null || true)"
    append_metric oci_new_blob_bytes "${uploaded_blob_bytes:-0}"

    local batch_duration_ms=""
    batch_duration_ms="$(jq -r 'select(.operation == "oci_blob_upload_batch") | .duration_ms // empty' "$observability_path" 2>/dev/null | tail -n1 || true)"
    if [[ -n "$batch_duration_ms" ]]; then
      awk -v ms="$batch_duration_ms" 'BEGIN { printf "oci_upload_batch_seconds=%.3f\n", ms / 1000 }' >> "$output_path"
    fi
  fi
}

verify_expected_cache_backend() {
  if ! grep -qE '^#[0-9]+( \[[^]]+\])? exporting cache to boringcache$' "$build_log"; then
    echo "Expected the managed type=boringcache exporter, but the build did not report 'exporting cache to boringcache'." >&2
    return 1
  fi
}

parse_tool_cache_args() {
  tool_cache_args=()
  while IFS= read -r tool_cache_entry; do
    tool_cache_entry="${tool_cache_entry#"${tool_cache_entry%%[![:space:]]*}"}"
    tool_cache_entry="${tool_cache_entry%"${tool_cache_entry##*[![:space:]]}"}"
    [[ -n "$tool_cache_entry" ]] || continue
    tool_cache_entry="${tool_cache_entry//\{CACHE_SCOPE\}/${CACHE_SCOPE:?Set CACHE_SCOPE}}"
    tool_cache_args+=(--tool-cache "$tool_cache_entry")
  done < <(printf '%s\n' "$docker_tool_cache" | tr ',' '\n')
}

write_sccache_stats_from_build_log() {
  grep -q 'BEGIN_BORINGCACHE_SCCACHE_STATS' "$build_log" || return 0

  mkdir -p benchmark-native-tool
  awk '
    /BEGIN_BORINGCACHE_SCCACHE_STATS/ { capture = 1; next }
    /END_BORINGCACHE_SCCACHE_STATS/ { capture = 0 }
    capture {
      sub(/^#[0-9]+[[:space:]]+[0-9.]+[[:space:]]+/, "")
      sub(/^#[0-9]+[[:space:]]+/, "")
      print
    }
  ' "$build_log" | sed '/^[[:space:]]*$/d' > benchmark-native-tool/sccache-stats.txt

  if ! grep -q 'Compile requests' benchmark-native-tool/sccache-stats.txt; then
    rm -f benchmark-native-tool/sccache-stats.txt
  fi
}

write_mountcache_log() {
  local output_path="${BENCHMARK_MOUNTCACHE_LOG_OUTPUT:-}"
  [[ -n "$output_path" ]] || return 0

  mkdir -p "$(dirname "$output_path")"
  grep -F 'boringcache cache mount' "$build_log" > "$output_path" || :
}


capture_proxy_status() {
  local output_path="${1:-$status_snapshot_path}"
  curl -fsS "http://127.0.0.1:${proxy_port}/_boringcache/status" -o "$output_path" 2>/dev/null || true
}

cache_from_requested() {
  [[ "$mode" == "rolling" ]] && { [[ -n "$cache_requested_from_refs" ]] || [[ -n "${CACHE_FROM:-}" ]]; }
}

cache_from_usable() {
  [[ "$cache_import_ready" == "true" ]] && { [[ -n "${CACHE_FROM:-}" ]] || [[ -n "$cache_used_from_refs" ]]; }
}

cache_from_import_arg_available() {
  [[ "$cache_import_ready" == "true" && -n "${CACHE_FROM:-}" ]]
}

require_readable_cache_import() {
  cache_from_requested || return 0

  if ! cache_from_usable; then
    echo "BoringCache Docker import had no usable refs." >&2
    echo "requested refs: ${cache_requested_from_refs}" >&2
    echo "used refs: ${cache_used_from_refs}" >&2
    echo "unreadable refs: ${cache_unreadable_from_refs}" >&2
    if [[ "$mode" == "rolling" && "$allow_rolling_bootstrap" == "true" ]]; then
      echo "Continuing without a readable import so this rolling run can publish the rolling-scope OCI alias." >&2
      return 0
    fi
    write_build_diagnostics
    exit 1
  fi

  if [[ "$cache_import_ready" != "true" ]]; then
    echo "BoringCache Docker import was not ready." >&2
    echo "requested refs: ${cache_requested_from_refs}" >&2
    echo "used refs: ${cache_used_from_refs}" >&2
    echo "unreadable refs: ${cache_unreadable_from_refs}" >&2
    if [[ "$mode" == "rolling" && "$allow_rolling_bootstrap" == "true" ]]; then
      echo "Continuing with the usable import subset so this rolling run can refresh the rolling-scope OCI alias." >&2
      return 0
    fi
    write_build_diagnostics
    exit 1
  fi
}

build_import_status() {
  if grep -Eq 'failed to configure .*cache importer|cache manifest.*(manifest unknown|not found)|importing cache manifest.*(manifest unknown|not found)' "$build_log"; then
    echo "not_found"
  elif grep -Eq 'inferred cache manifest type|importing cache manifest' "$build_log"; then
    echo "ok"
  elif cache_from_requested && ! cache_from_usable && [[ "$mode" == "rolling" && "$allow_rolling_bootstrap" == "true" ]]; then
    echo "bootstrap_miss"
  elif cache_from_requested && ! cache_from_usable; then
    echo "proxy_unreadable"
  else
    echo "none"
  fi
}

write_build_diagnostics() {
  local output_path="${BENCHMARK_DIAGNOSTICS_OUTPUT:-}"
  [[ -n "$output_path" ]] || return 0

  local cached_steps=""
  cached_steps="$(grep -Ec '^#[0-9]+( \[[^]]+\])? CACHED$' "$build_log" || true)"
  local observability_path="${BORINGCACHE_OBSERVABILITY_JSONL_PATH:-}"

  mkdir -p "$(dirname "$output_path")"
  {
    echo "strategy=boringcache"
    echo "buildkit_backend=boringcache"
    echo "mode=${mode}"
    echo "docker_build_family=${docker_build_family}"
    echo "builder=${BUILDER:-}"
    echo "cache_scope=${CACHE_SCOPE:-}"
    echo "cache_from=${CACHE_FROM:-}"
    echo "cache_import_ready=${cache_import_ready}"
    echo "cache_requested_from_refs=${cache_requested_from_refs}"
    echo "cache_used_from_refs=${cache_used_from_refs}"
    echo "cache_unreadable_from_refs=${cache_unreadable_from_refs}"
    echo "cache_promotion_refs=${cache_promotion_refs}"
    echo "blob_download_concurrency_override=${BORINGCACHE_BLOB_DOWNLOAD_CONCURRENCY:-}"
    echo "blob_prefetch_concurrency_override=${BORINGCACHE_BLOB_PREFETCH_CONCURRENCY:-}"
    echo "oci_stream_through_min_bytes=${BORINGCACHE_OCI_STREAM_THROUGH_MIN_BYTES:-}"
    printf 'cache_args='
    printf '%q ' ${cache_args[@]+"${cache_args[@]}"}
    printf '\n'
    echo "import_status=$(build_import_status)"
    echo "cached_steps=${cached_steps}"
    echo "import_lines<<EOF"
    grep -E 'importing cache manifest|failed to configure .*cache importer|inferred cache manifest type' "$build_log" || true
    echo "EOF"
    echo "export_lines<<EOF"
    grep -E 'exporting cache to boringcache|DONE [0-9.]+s$' "$build_log" | tail -n 80 || true
    echo "EOF"
    echo "proxy_summary<<EOF"
    grep -E 'Mode:|OCI Human Tags|Internal Registry Root Tag|Startup mode|Full-tag hydration|OCI body hydration|OCI HEAD|SESSION tool=oci|KV flush|root publish|error|warn' "$proxy_log" | tail -n 160 || true
    echo "EOF"
    echo "proxy_status<<EOF"
    if [[ -s "$status_snapshot_path" ]]; then
      cat "$status_snapshot_path"
    fi
    echo "EOF"
    echo "slow_done_lines<<EOF"
    grep -E '^#[0-9]+ DONE [0-9]+(\.[0-9]+)?s$' "$build_log" | tail -n 80 || true
    echo "EOF"
    echo "observability_jsonl=${observability_path}"
    if [[ -s benchmark-native-tool/sccache-stats.txt ]]; then
      echo "sccache_stats<<EOF"
      cat benchmark-native-tool/sccache-stats.txt
      echo "EOF"
    fi
    if [[ -n "$observability_path" && -s "$observability_path" ]]; then
      printf 'observability_events='
      wc -l < "$observability_path" | tr -d ' '
      printf '\n'
      echo "observability_summary<<EOF"
      grep -E 'cache_session_summary|oci_blob_upload|upload_session_commit|cache_finalize_publish|receipt|429|rate' "$observability_path" | tail -n 160 || true
      echo "EOF"
    fi
  } > "$output_path"
}

prepare_build_command() {
  build_command=()

  case "$docker_build_family" in
    buildx-build)
      build_command=(
        docker buildx build
        --file "$DOCKERFILE_PATH"
        --tag "$IMAGE_TAG"
        --progress=plain
      )
      build_command+=("${extra_args[@]}")
      build_command+=("${wrapped_cache_args[@]}")
      build_command+=("${output_args[@]}")
      build_command+=("$BENCHMARK_DOCKER_CONTEXT")
      ;;
    bake)
      [[ -n "$docker_working_directory" ]] || { echo "BENCHMARK_DOCKER_WORKING_DIRECTORY is required for Bake" >&2; return 1; }
      [[ -n "$docker_bake_file" ]] || { echo "DOCKER_BAKE_FILE is required for Bake" >&2; return 1; }
      [[ -n "$docker_bake_group" ]] || { echo "DOCKER_BAKE_GROUP is required for Bake" >&2; return 1; }
      build_command=(
        docker buildx bake
        --file "$docker_bake_file"
        --progress=plain
      )
      build_command+=("${extra_args[@]}")
      build_command+=("${wrapped_cache_args[@]}")
      build_command+=("${output_args[@]}")
      build_command+=("$docker_bake_group")
      ;;
    compose)
      [[ -n "$docker_working_directory" ]] || { echo "BENCHMARK_DOCKER_WORKING_DIRECTORY is required for Compose" >&2; return 1; }
      [[ -n "$docker_compose_file" ]] || { echo "DOCKER_COMPOSE_FILE is required for Compose" >&2; return 1; }
      [[ -n "$docker_compose_command" ]] || { echo "DOCKER_COMPOSE_COMMAND is required for Compose" >&2; return 1; }
      build_command=(docker compose --file "$docker_compose_file")
      while IFS= read -r argument; do
        [[ -n "$argument" ]] && build_command+=("$argument")
      done <<< "$docker_compose_command"
      ;;
    *)
      echo "Unknown Docker build family: ${docker_build_family}" >&2
      return 1
      ;;
  esac
}

capture_build_plan() {
  [[ "$docker_build_family" == "bake" || "$docker_build_family" == "compose" ]] || return 0

  local plan_path="${BENCHMARK_BAKE_PLAN_OUTPUT:-}"
  if [[ -z "$plan_path" ]]; then
    plan_path="$(mktemp /tmp/boringcache-bake-plan.XXXXXX.json)"
  else
    mkdir -p "$(dirname "$plan_path")"
  fi

  (
    cd "$docker_working_directory"
    boringcache "${boringcache_args[@]}" --dry-run --json -- "${build_command[@]}"
  ) > "$plan_path"

  jq -e '.buildkit_cache.build_targets | length > 0' "$plan_path" >/dev/null
  resolved_cache_tags_csv="$(
    jq -r '
      .tag_plans[].transport_refs[]?
      | select(.role == "save")
      | .reference
      | capture("ref=[^,]*/cache:(?<tag>[^,]+)").tag
    ' "$plan_path" | awk '!seen[$0]++' | paste -sd, -
  )"
  if [[ -z "$resolved_cache_tags_csv" ]]; then
    echo "BoringCache ${docker_build_family} dry-run did not expose any save cache refs." >&2
    return 1
  fi
}

run_wrapped_boringcache_build() {
  local phase_hint="cold"
  if [[ "$mode" == "rolling" ]]; then
    phase_hint="commit"
  fi

  boringcache_args=(
    docker
    --workspace "${BENCHMARK_WORKSPACE:?Set BENCHMARK_WORKSPACE}"
    --tag "${CACHE_SCOPE:?Set CACHE_SCOPE}"
    --cache-mode max
    --no-platform
    --no-git
    --metadata-hint "benchmark=${BENCHMARK_ID:-docker}"
    --metadata-hint "phase=${phase_hint}"
    --metadata-hint "lane=${CACHE_LANE:-fresh}"
    --metadata-hint "backend=boringcache"
    --fail-on-cache-error
  )
  boringcache_args+=("${tool_cache_args[@]}")

  local wrapped_cache_args=()
  local cache_arg
  for cache_arg in "${cache_args[@]}"; do
    [[ "$cache_arg" == "--no-cache" ]] && wrapped_cache_args+=("$cache_arg")
  done

  prepare_build_command
  capture_build_plan

  : > "$build_log"
  set +e
  if [[ "$docker_build_family" == "bake" || "$docker_build_family" == "compose" ]]; then
    (
      cd "$docker_working_directory"
      DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain BORINGCACHE_TIMING_TRACE=1 boringcache "${boringcache_args[@]}" -- "${build_command[@]}"
    ) 2>&1 | tee "$build_log"
  else
    DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain BORINGCACHE_TIMING_TRACE=1 boringcache "${boringcache_args[@]}" -- "${build_command[@]}" 2>&1 | tee "$build_log"
  fi
  status=${PIPESTATUS[0]}
  set -e
}


attempt=1
while true; do
  cache_args=()
  extra_args=()
  output_args=()
  tool_cache_args=()
  while IFS= read -r arg; do
    [[ -n "$arg" ]] || continue
    extra_args+=("$arg")
  done <<< "${DOCKER_BUILD_EXTRA_ARGS:-}"
  parse_tool_cache_args

  case "$build_output" in
    none)
      ;;
    load)
      output_args+=(--load)
      ;;
    local-registry)
      output_args+=(--push)
      ;;
    *)
      echo "Unknown BENCHMARK_BUILD_OUTPUT: ${build_output}" >&2
      exit 1
      ;;
  esac

  if [[ "$mode" == "rolling" ]]; then
    :
  elif [[ "$mode" == "fresh" ]]; then
    cache_args=(--no-cache)
  else
    echo "Unknown build mode: $mode" >&2
    exit 1
  fi

  run_wrapped_boringcache_build

  if [[ "$status" -eq 0 ]]; then
    verify_expected_cache_backend
    import_status="$(build_import_status)"
    write_sccache_stats_from_build_log
    write_mountcache_log
    if [[ "$mode" =~ ^(rolling|fresh)$ ]] && grep -Eq "$cache_export_pattern" "$build_log"; then
      capture_proxy_status
      write_build_metrics
      write_build_diagnostics
      echo "Build succeeded but managed cache export reported an error; failing benchmark." >&2
      tail -n 200 "$build_log" || true
      tail -n 400 "$proxy_log" || true
      exit 1
    fi
    capture_proxy_status
    echo "=== Managed cache log (${mode}, last 200 lines) ==="
    tail -n 200 "$proxy_log" 2>/dev/null || true
    echo "=== End managed cache log ==="
    write_build_metrics
    write_build_diagnostics
    break
  fi

  if [[ "$attempt" -ge "$max_attempts" ]]; then
    echo "Build (${mode}) failed after ${max_attempts} attempts" >&2
    tail -n 200 "$build_log" || true
    tail -n 400 "$proxy_log" || true
    write_build_diagnostics
    write_mountcache_log
    exit "$status"
  fi

done
