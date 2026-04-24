#!/usr/bin/env bash
set -euo pipefail

tag_name="${1:-${GITHUB_REF_NAME:-}}"
version="${tag_name#v}"
release_dir=".build/release"
app_bundle="${release_dir}/AgentTally.app"
archive_path="${release_dir}/AgentTally.app.zip"
checksum_path="${release_dir}/AgentTally.app.zip.sha256"

if [[ -z "${tag_name}" ]]; then
  echo "release tag is required" >&2
  exit 1
fi

if [[ ! "${tag_name}" =~ ^v[0-9].* ]]; then
  echo "release tag must start with 'v' (for example: v0.5)" >&2
  exit 1
fi

mise trust -y mise.toml
mise install
AGENTTALLY_VERSION="${version}" mise run check

cd "${release_dir}"
ditto -c -k --sequesterRsrc --keepParent AgentTally.app AgentTally.app.zip
shasum -a 256 AgentTally.app.zip > AgentTally.app.zip.sha256
cd - >/dev/null

gh release create "${tag_name}" \
  "${archive_path}" \
  "${checksum_path}" \
  --generate-notes
