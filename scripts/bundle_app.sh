#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-debug}"
app_dir=".build/${configuration}/ClaudeCost.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
executable=".build/${configuration}/ClaudeCost"
helper=".build/claudecost-usage-helper"
plist_path="${contents_dir}/Info.plist"

if [[ ! -x "${executable}" ]]; then
  echo "missing executable: ${executable}" >&2
  exit 1
fi

if [[ ! -x "${helper}" ]]; then
  echo "missing helper: ${helper}" >&2
  exit 1
fi

rm -rf "${app_dir}"
mkdir -p "${macos_dir}"

cp "${executable}" "${macos_dir}/ClaudeCost"
cp "${helper}" "${macos_dir}/claudecost-usage-helper"
bash scripts/generate_info_plist.sh "${plist_path}"
