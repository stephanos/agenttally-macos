#!/usr/bin/env bash
set -euo pipefail

tag_name="${1:-${GITHUB_REF_NAME:-}}"
release_dir=".build/release"
app_bundle="${release_dir}/ClaudeCost.app"
archive_path="${release_dir}/ClaudeCost.app.zip"
checksum_path="${release_dir}/ClaudeCost.app.zip.sha256"

mise trust -y mise.toml
mise install
mise run check

cd "${release_dir}"
ditto -c -k --sequesterRsrc --keepParent ClaudeCost.app ClaudeCost.app.zip
shasum -a 256 ClaudeCost.app.zip > ClaudeCost.app.zip.sha256
cd - >/dev/null

if [[ -z "${tag_name}" ]]; then
  echo "Skipping GitHub release publish because no tag was provided."
  exit 0
fi

gh release create "${tag_name}" \
  "${archive_path}" \
  "${checksum_path}" \
  --generate-notes
