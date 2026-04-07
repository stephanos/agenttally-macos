#!/usr/bin/env bash
set -euo pipefail

mkdir -p .build

# Compile the real app target first so package-level Swift/concurrency issues are
# caught by `mise run test`, not only by the release bundle build in CI.
bash scripts/build_swift.sh

swiftc \
  -module-name ClaudeCostTestHarness \
  -o .build/claudecost-test-harness \
  Sources/ClaudeCost/AppState.swift \
  Sources/ClaudeCost/LoginItemManager.swift \
  Sources/ClaudeCost/MenuRowsBuilder.swift \
  Sources/ClaudeCost/StatusPresenter.swift \
  Sources/ClaudeCost/TimeUtils.swift \
  Sources/ClaudeCost/UsageFetcher.swift \
  Sources/ClaudeCost/UsagePayloadParser.swift \
  Sources/ClaudeCost/UsageRefreshController.swift \
  Tests/TestSupport.swift \
  Tests/StatusPresenterHarness.swift \
  Tests/UsageRefreshControllerHarness.swift \
  Tests/UsageFetcherHarness.swift \
  Tests/UsagePayloadParserHarness.swift \
  Tests/TimeUtilsHarness.swift \
  Tests/MenuRowsHarness.swift \
  Tests/LoginItemHarness.swift \
  Tests/HarnessMain.swift

.build/claudecost-test-harness
