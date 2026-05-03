#!/usr/bin/env bash
set -euo pipefail

mkdir -p .build

# Compile the real app target first so package-level Swift/concurrency issues are
# caught by `mise run test`, not only by the release bundle build in CI.
bash scripts/build_swift.sh

mapfile -t source_files < <(
  find Sources/AgentTally \
    -name '*.swift' \
    ! -path 'Sources/AgentTally/App/*' \
    | sort
)
mapfile -t test_files < <(
  find Tests \
    -name '*.swift' \
    ! -name 'HarnessMain.swift' \
    | sort
)

swiftc \
  -module-name AgentTallyTestHarness \
  -o .build/agenttally-test-harness \
  "${source_files[@]}" \
  "${test_files[@]}" \
  Tests/HarnessMain.swift

.build/agenttally-test-harness
