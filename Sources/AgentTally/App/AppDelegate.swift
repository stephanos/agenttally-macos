import AppKit
import Foundation
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem?
  private var timer: Timer?
  private var refreshTask: Task<Void, Never>?
  private var state = AppState()
  private var lastSuccessfulAgentData: [AgentKind: AgentRawData] = [:]
  private var lastUsageDataFingerprints: [AgentKind: UsageDataFingerprint] = [:]
  private var usageFileSummaryCache = UsageFileSummaryCache()
  private let loginItemManager = LoginItemManager()
  private let refreshIntervalPreference = RefreshIntervalPreference()
  private let refreshGenerationGate = RefreshGenerationGate()
  private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: self,
    userDriverDelegate: self
  )
  private var refreshInterval = RefreshIntervalOption.defaultValue
  private var startAtLoginViewState = StartAtLoginViewState.make(status: .notRegistered)
  private var softwareUpdateViewState = SoftwareUpdateViewState.idle

  func applicationDidFinishLaunching(_ notification: Notification) {
    _ = updaterController

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem

    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    refreshInterval = refreshIntervalPreference.selectedInterval()
    startAtLoginViewState = loginItemManager.configureOnLaunch()
    rescheduleRefreshTimer()
    renderTitle()
    refreshUsage()
  }

  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    timer = nil
    refreshTask?.cancel()
    refreshTask = nil
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    rebuildMenu(menu)
  }

  @objc
  private func refreshTimerFired() {
    rescheduleRefreshTimer()
    refreshUsage()
  }

  @objc
  private func refreshMenuItemSelected() {
    rescheduleRefreshTimer()
    refreshUsage()
  }

  @objc
  private func refreshIntervalMenuItemSelected(_ sender: NSMenuItem) {
    guard case .refreshInterval(let option) = sender.representedObject as? MenuActionKind else {
      return
    }

    refreshInterval = option
    refreshIntervalPreference.setSelectedInterval(option)
    rescheduleRefreshTimer()
    refreshMenuIfNeeded()
  }

  @objc
  private func startAtLoginMenuItemSelected(_ sender: NSMenuItem) {
    let shouldEnable = sender.state != .on
    startAtLoginViewState = loginItemManager.setEnabled(shouldEnable)
    refreshMenuIfNeeded()
  }

  @objc
  private func checkForUpdatesMenuItemSelected(_ sender: NSMenuItem) {
    updaterController.checkForUpdates(sender)
  }

  @objc
  private func quitMenuItemSelected() {
    NSApplication.shared.terminate(nil)
  }

  private func rescheduleRefreshTimer() {
    timer?.invalidate()
    let timer = Timer.scheduledTimer(
      timeInterval: currentRefreshInterval(),
      target: self,
      selector: #selector(refreshTimerFired),
      userInfo: nil,
      repeats: false
    )
    timer.tolerance = refreshInterval.timerTolerance
    self.timer = timer
  }

  private func currentRefreshInterval() -> TimeInterval {
    refreshInterval.duration
  }

  private func refreshUsage() {
    guard
      let request = UsageRefreshController.beginRefresh(
        from: state,
        isOnBatteryPower: PowerSource.isOnBatteryPower()
      )
    else {
      return
    }

    state = request.state
    renderTitle()

    refreshTask?.cancel()
    refreshTask = Task {
      let generation = self.refreshGenerationGate.nextGeneration()

      let usageDataScan = await Task.detached(priority: .utility) {
        UsageDataScanner.currentScan()
      }.value

      // Check generation after usageDataScan fetch
      guard self.refreshGenerationGate.isCurrent(generation) else {
        return
      }

      let agentsToRefresh = UsageRefreshController.agentsNeedingRefresh(
        pricingMode: request.pricingMode,
        currentUsageDataScan: usageDataScan,
        cachedUsageDataFingerprints: self.lastUsageDataFingerprints,
        cachedAgentData: self.lastSuccessfulAgentData,
        lastErrorByAgent: self.state.lastErrorByAgent
      )

      var nextErrorByAgent = self.state.lastErrorByAgent
      var nextUsageFileSummaryCache = self.usageFileSummaryCache
      for agent in agentsToRefresh {
        do {
          let isOffline = request.pricingMode == .offline
          let cache = nextUsageFileSummaryCache
          let result = try await Task.detached(priority: .utility) {
            try await UsageFetcher.fetchUsage(
              offline: isOffline,
              agents: [agent],
              context: .live,
              cache: cache
            )
          }.value
          let snapshot = result.snapshot
          nextUsageFileSummaryCache = result.cache

          // Check generation after each fetch
          guard self.refreshGenerationGate.isCurrent(generation) else {
            return
          }

          self.cache(snapshot: snapshot, usageDataScan: usageDataScan)
          self.usageFileSummaryCache = nextUsageFileSummaryCache
          nextErrorByAgent.removeValue(forKey: agent)
        } catch {
          guard !Task.isCancelled else {
            return
          }
          nextErrorByAgent[agent] = error.localizedDescription
          NSLog(
            "agenttally %@ refresh failed: %@",
            agent.displayName,
            error.localizedDescription
          )
        }
      }

      // Check generation before applying state
      guard self.refreshGenerationGate.isCurrent(generation) else {
        return
      }

      self.applyRefreshSuccess(
        self.cachedSnapshot(),
        pricingMode: request.pricingMode,
        lastUsageDetectedAtByAgent: usageDataScan.lastUsageDetectedAtByAgent,
        lastErrorByAgent: nextErrorByAgent
      )
    }
  }

  private func cache(snapshot: UsageSnapshot, usageDataScan: UsageDataScan) {
    for rawData in snapshot.agents {
      guard let agent = AgentKind(displayName: rawData.name) else {
        continue
      }

      lastSuccessfulAgentData[agent] = rawData
      if let fingerprint = usageDataScan.agents[agent]?.fingerprint {
        lastUsageDataFingerprints[agent] = fingerprint
      }
    }
  }

  private func cachedSnapshot() -> UsageSnapshot {
    UsageSnapshot(
      agents: AgentKind.allCases.compactMap { agent in
        lastSuccessfulAgentData[agent]
      }
    )
  }

  private func applyRefreshSuccess(
    _ snapshot: UsageSnapshot,
    pricingMode: PricingRefreshMode,
    lastUsageDetectedAtByAgent: [AgentKind: Date],
    lastErrorByAgent: [AgentKind: String]
  ) {
    state = UsageRefreshController.applySuccess(
      snapshot: snapshot,
      pricingMode: pricingMode,
      lastUsageDetectedAtByAgent: lastUsageDetectedAtByAgent,
      lastErrorByAgent: lastErrorByAgent,
      to: state
    )
    renderTitle()
    refreshMenuIfNeeded()
  }

  private func applyRefreshFailure(_ error: Error) {
    state = UsageRefreshController.applyFailure(error: error, to: state)
    renderTitle()
    NSLog("agenttally refresh failed: %@", error.localizedDescription)
    refreshMenuIfNeeded()
  }

  private func renderTitle() {
    setStatusAppearance(
      title: StatusPresenter.title(for: state),
      showWarningSymbol: StatusPresenter.shouldShowWarningSymbol(for: state)
    )
  }

  private func setStatusAppearance(title: String, showWarningSymbol: Bool) {
    guard let button = statusItem?.button else {
      return
    }

    button.title = title
    button.image = showWarningSymbol ? warningSymbolImage() : nil
    button.imagePosition = .imageLeading
  }

  private func warningSymbolImage() -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    let image = NSImage(
      systemSymbolName: "exclamationmark.triangle.fill",
      accessibilityDescription: "Warning"
    )?
    .withSymbolConfiguration(configuration)
    image?.isTemplate = true
    return image
  }

  private func refreshMenuIfNeeded() {
    guard let menu = statusItem?.menu else {
      return
    }
    rebuildMenu(menu)
  }

  private func rebuildMenu(_ menu: NSMenu) {
    let rows = MenuRowsBuilder.rows(
      for: state,
      startAtLogin: startAtLoginViewState,
      softwareUpdate: softwareUpdateViewState,
      refreshInterval: refreshInterval,
      appVersion: appVersion()
    )
    MenuRenderer.render(menu: menu, rows: rows, target: self, selectorProvider: selector)
  }

  private func appVersion() -> String? {
    if let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String, !shortVersion.isEmpty
    {
      return shortVersion
    }

    if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      !bundleVersion.isEmpty
    {
      return bundleVersion
    }

    return nil
  }

  private func selector(for action: MenuActionKind) -> Selector {
    switch action {
    case .startAtLogin:
      return #selector(startAtLoginMenuItemSelected(_:))
    case .refresh:
      return #selector(refreshMenuItemSelected)
    case .refreshInterval:
      return #selector(refreshIntervalMenuItemSelected(_:))
    case .checkForUpdates:
      return #selector(checkForUpdatesMenuItemSelected(_:))
    case .quit:
      return #selector(quitMenuItemSelected)
    }
  }

  private func noteAvailableUpdate(version: String) {
    softwareUpdateViewState = SoftwareUpdateViewState(availableVersion: version)
    refreshMenuIfNeeded()
  }
}

extension AppDelegate: SPUUpdaterDelegate {
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    noteAvailableUpdate(version: item.displayVersionString)
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    softwareUpdateViewState = .idle
    refreshMenuIfNeeded()
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    softwareUpdateViewState = .idle
    refreshMenuIfNeeded()
  }
}

extension AppDelegate: SPUStandardUserDriverDelegate {
  nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem,
    andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    let version = update.displayVersionString
    Task { @MainActor [weak self] in
      self?.noteAvailableUpdate(version: version)
    }
    return false
  }
}
