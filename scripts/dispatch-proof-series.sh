#!/usr/bin/env bash
set -euo pipefail

repo="boringcache/docker-cache-proofs"
workflow="Docker Benchmark"
workflow_ref="main"
case_id=""
fresh_ref="main"
rolling_bootstrap_ref="main"
build_output="none"
lane_filter="all"
cache_scope_suffix=""
cli_version=""
buildkit_image=""
run_fresh="true"
run_rolling="true"
include_rolling_bootstrap="true"
wait_for_runs="true"
dry_run="false"
warm_replay="false"
watch_interval_seconds="${GH_RUN_WATCH_INTERVAL_SECONDS:-60}"
rust_target_cache="false"
compare_rust_target="false"
rolling_refs=()

usage() {
  cat <<'USAGE'
Usage: scripts/dispatch-proof-series.sh --case CASE_ID [options]

Dispatch a Painful Builds Docker lane in the public fresh + ordered rolling shape.
By default it runs:
  1. fresh on ref key "main"
  2. rolling on ref key "main" to bootstrap/update the rolling cache scope
  3. rolling1, rolling2, rolling3... from cases/CASE_ID.json in numeric order

Options:
  --case CASE_ID                  Case manifest id, e.g. phentrieve-api
  --repo OWNER/REPO               Target proof repo (default: boringcache/docker-cache-proofs)
  --workflow NAME_OR_FILE         Workflow name or file (default: Docker Cache Proof)
  --ref GIT_REF                   Workflow ref to dispatch (default: main)
  --fresh-ref REF_KEY             Ref key for fresh run (default: main)
  --rolling-bootstrap-ref REF_KEY Ref key for rolling bootstrap (default: main)
  --rolling-ref REF_KEY           Add one rolling ref key; repeatable
  --rolling-refs A,B,C            Add comma-separated rolling ref keys
  --build-output MODE             none, load, local-registry, or ghcr (default: none)
  --lane-filter FILTER            all, buildkit, gha-buildkit, or registry-buildkit (default: all)
  --cache-scope-suffix SUFFIX     Isolate the stable rolling cache scope
  --cli-version TAG               Exact CLI release or immutable canary tag
  --buildkit-image IMAGE          Exact managed BuildKit image reference
  --rust-target-cache             Offload and measure the case's declared Cargo target cache mount
  --compare-rust-target           Run each selected phase once without and once with target offload
  --warm-replay                   Replay the last rolling ref once after the commit series
  --skip-fresh                    Do not dispatch the fresh lane
  --skip-rolling                  Do not dispatch rolling lanes
  --skip-rolling-bootstrap        Do not dispatch rolling bootstrap/update on main
  --no-wait                       Dispatch and return without waiting
  --dry-run                       Print commands without dispatching
USAGE
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case)
      case_id="$2"
      shift 2
      ;;
    --repo)
      repo="$2"
      shift 2
      ;;
    --workflow)
      workflow="$2"
      shift 2
      ;;
    --ref)
      workflow_ref="$2"
      shift 2
      ;;
    --fresh-ref)
      fresh_ref="$2"
      shift 2
      ;;
    --rolling-bootstrap-ref)
      rolling_bootstrap_ref="$2"
      shift 2
      ;;
    --rolling-ref)
      rolling_refs+=("$2")
      shift 2
      ;;
    --rolling-refs)
      IFS=',' read -r -a parsed_refs <<< "$2"
      for ref_key in "${parsed_refs[@]}"; do
        [[ -n "$ref_key" ]] && rolling_refs+=("$ref_key")
      done
      shift 2
      ;;
    --build-output)
      build_output="$2"
      shift 2
      ;;
    --lane-filter)
      lane_filter="$2"
      shift 2
      ;;
    --cache-scope-suffix)
      cache_scope_suffix="$2"
      shift 2
      ;;
    --cli-version)
      cli_version="$2"
      shift 2
      ;;
    --buildkit-image)
      buildkit_image="$2"
      shift 2
      ;;
    --rust-target-cache)
      rust_target_cache="true"
      shift
      ;;
    --compare-rust-target)
      compare_rust_target="true"
      shift
      ;;
    --warm-replay)
      warm_replay="true"
      shift
      ;;
    --skip-fresh)
      run_fresh="false"
      shift
      ;;
    --skip-rolling)
      run_rolling="false"
      shift
      ;;
    --skip-rolling-bootstrap)
      include_rolling_bootstrap="false"
      shift
      ;;
    --no-wait)
      wait_for_runs="false"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$case_id" ]]; then
  echo "--case is required" >&2
  usage >&2
  exit 1
fi

case "$build_output" in
  none | load | local-registry | ghcr)
    ;;
  *)
    echo "Unsupported build output: $build_output" >&2
    exit 1
    ;;
esac

case "$lane_filter" in
  all | buildkit | gha-buildkit | registry-buildkit)
    ;;
  *)
    echo "Unsupported lane filter: $lane_filter" >&2
    exit 1
    ;;
esac

require_tool gh
require_tool jq

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case_file="${repo_root}/cases/${case_id}.json"

if [[ ! -f "$case_file" ]]; then
  echo "Unknown case manifest: ${case_file}" >&2
  exit 1
fi

if [[ "${#rolling_refs[@]}" -eq 0 ]]; then
  while IFS= read -r ref_key; do
    [[ -n "$ref_key" ]] && rolling_refs+=("$ref_key")
  done < <(
    jq -r '
      .refs
      | keys
      | map(select(test("^rolling[0-9]+$")))
      | sort_by(capture("^rolling(?<n>[0-9]+)$").n | tonumber)
      | .[]
    ' "$case_file"
  )
fi

wait_for_run() {
  local title_prefix="$1"
  local started_at="$2"
  local run_id=""
  local run_url=""

  for _ in $(seq 1 30); do
    runs_json="$(gh run list --repo "$repo" --workflow "$workflow" --event workflow_dispatch --limit 50 --json databaseId,displayTitle,createdAt,url,status,conclusion)"
    run_id="$(
      jq -r --arg title "$title_prefix" --arg started "$started_at" '
        [.[] | select(.createdAt >= $started and (.displayTitle | startswith($title)))]
        | sort_by(.createdAt)
        | reverse
        | .[0].databaseId // empty
      ' <<< "$runs_json"
    )"
    run_url="$(
      jq -r --arg title "$title_prefix" --arg started "$started_at" '
        [.[] | select(.createdAt >= $started and (.displayTitle | startswith($title)))]
        | sort_by(.createdAt)
        | reverse
        | .[0].url // empty
      ' <<< "$runs_json"
    )"
    if [[ -n "$run_id" ]]; then
      echo "$run_url"
      # A Docker proof can run for well over ten minutes. The gh default polls
      # every three seconds, which can exhaust the authenticated REST quota
      # during a multi-commit series.
      gh run watch "$run_id" --repo "$repo" --exit-status --interval "$watch_interval_seconds"
      return 0
    fi
    sleep "$watch_interval_seconds"
  done

  echo "Could not find dispatched run for ${title_prefix}" >&2
  exit 1
}

dispatch_one() {
  local ref_key="$1"
  local lane="$2"
  local target_cache="$3"
  local target_label="off"
  if [[ "$target_cache" == "true" ]]; then
    target_label="on"
  fi
  local effective_lane_filter="$lane_filter"
  if [[ "$compare_rust_target" == "true" && "$target_cache" == "true" && "$lane_filter" == "all" ]]; then
    effective_lane_filter="buildkit"
  fi
  local title_prefix="${case_id} | ${ref_key} | ${lane} | output=${build_output} | rust-target=${target_label}"
  local started_at=""
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  cmd=(
    gh workflow run "$workflow"
    --repo "$repo"
    --ref "$workflow_ref"
    -f "case_id=${case_id}"
    -f "ref_key=${ref_key}"
    -f "cache_lane=${lane}"
    -f "build_output=${build_output}"
    -f "lane_filter=${effective_lane_filter}"
    -f "cache_scope_suffix=${cache_scope_suffix}"
    -f "rust_target_cache=${target_cache}"
  )
  if [[ -n "$cli_version" ]]; then
    cmd+=(-f "cli_version=${cli_version}")
  fi
  if [[ -n "$buildkit_image" ]]; then
    cmd+=(-f "buildkit_image=${buildkit_image}")
  fi

  printf 'Dispatching:'
  printf ' %q' "${cmd[@]}"
  printf '\n'

  if [[ "$dry_run" == "true" ]]; then
    return 0
  fi

  "${cmd[@]}"

  if [[ "$wait_for_runs" == "true" ]]; then
    wait_for_run "$title_prefix" "$started_at"
  fi
}

dispatch_variants() {
  local ref_key="$1"
  local lane="$2"
  if [[ "$compare_rust_target" == "true" ]]; then
    dispatch_one "$ref_key" "$lane" false
    dispatch_one "$ref_key" "$lane" true
  else
    dispatch_one "$ref_key" "$lane" "$rust_target_cache"
  fi
}

if [[ "$run_fresh" == "true" ]]; then
  dispatch_variants "$fresh_ref" fresh
fi

if [[ "$run_rolling" == "true" ]]; then
  if [[ "$include_rolling_bootstrap" == "true" ]]; then
    dispatch_variants "$rolling_bootstrap_ref" rolling
  fi
  for ref_key in "${rolling_refs[@]}"; do
    dispatch_variants "$ref_key" rolling
  done
  if [[ "$warm_replay" == "true" && "${#rolling_refs[@]}" -gt 0 ]]; then
    last_rolling_index=$((${#rolling_refs[@]} - 1))
    dispatch_variants "${rolling_refs[$last_rolling_index]}" rolling
  fi
fi
