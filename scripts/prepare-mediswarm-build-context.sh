#!/usr/bin/env bash
set -euo pipefail

variant="${1:?variant is required}"
source_dir="$(pwd)"
context_dir="${source_dir}/benchmark-context"
mediswarm_dir="${context_dir}/MediSwarm"

case "$variant" in
  odelia|stamp) ;;
  *)
    echo "Unsupported MediSwarm image variant: ${variant}" >&2
    exit 1
    ;;
esac

git submodule update --init --depth 1 docker_config/NVFlare

rm -rf "$context_dir"
mkdir -p "$mediswarm_dir"
git archive --format=tar HEAD | tar -x -C "$mediswarm_dir"
mkdir -p "$mediswarm_dir/docker_config/NVFlare"
git -C docker_config/NVFlare archive --format=tar HEAD \
  | tar -x -C "$mediswarm_dir/docker_config/NVFlare"

version="$(./scripts/build/getVersionNumber.sh)"
container_version_id="$(git rev-parse --short HEAD)"

sed -i.bak \
  -e "s#__REPLACED_BY_CURRENT_VERSION_NUMBER_WHEN_BUILDING_DOCKER_IMAGE__#${version}#g" \
  -e "s#__REPLACED_BY_CONTAINER_VERSION_IDENTIFIER_WHEN_BUILDING_DOCKER_IMAGE__#${container_version_id}#g" \
  "$mediswarm_dir/docker_config/master_template.yml"
rm -f "$mediswarm_dir/docker_config/master_template.yml.bak"

if [[ -f "$mediswarm_dir/docker_config/master_template_STAMP.yml" ]]; then
  sed -i.bak \
    -e "s#__REPLACED_BY_CURRENT_VERSION_NUMBER_WHEN_BUILDING_DOCKER_IMAGE__#${version}#g" \
    -e "s#__REPLACED_BY_CONTAINER_VERSION_IDENTIFIER_WHEN_BUILDING_DOCKER_IMAGE__#${container_version_id}#g" \
    "$mediswarm_dir/docker_config/master_template_STAMP.yml"
  rm -f "$mediswarm_dir/docker_config/master_template_STAMP.yml.bak"
fi

if [[ "$variant" == "odelia" ]]; then
  ./scripts/build/_cacheAndCopyPretrainedModelWeights.sh "$context_dir"
fi
