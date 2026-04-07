#!/usr/bin/env bash
set -euo pipefail

mkdir -p .build
bun build --compile --minify ./tooling/usage-helper.ts --outfile .build/claudecost-usage-helper
