#!/usr/bin/env bash
set -euo pipefail

l10n_sha="${1:?localization commit is required}"
target="external/l10n"

mkdir -p "$(dirname "$target")"
git init "$target"
git -C "$target" remote add origin https://github.com/mozilla/fxa-content-server-l10n.git
git -C "$target" -c protocol.version=2 fetch --depth=1 origin "$l10n_sha"
git -C "$target" checkout --detach FETCH_HEAD

actual_sha="$(git -C "$target" rev-parse HEAD)"
if [[ "$actual_sha" != "$l10n_sha" ]]; then
  echo "Prepared localization ${actual_sha}, expected ${l10n_sha}" >&2
  exit 1
fi
