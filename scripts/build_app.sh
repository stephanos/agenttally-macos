#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-debug}"
if [[ "${configuration}" == "release" ]]; then
  bash scripts/build_swift.sh -c release
else
  bash scripts/build_swift.sh
fi
bash scripts/bundle_app.sh "${configuration}"
