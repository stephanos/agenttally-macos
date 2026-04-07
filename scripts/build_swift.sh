#!/usr/bin/env bash
set -euo pipefail

# Clear module caches so copied/moved working trees do not retain absolute-path
# references from an older checkout location.
find .build -type d -name ModuleCache -prune -exec rm -rf {} + 2>/dev/null || true

swift build "$@"
