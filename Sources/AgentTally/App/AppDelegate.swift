import AppKit
import Foundation
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let pluggedInRefreshInterval: TimeInterval = 60
  private let batteryRefreshInterval: TimeInterval = 120

  private var statusItem: NSStatusItem?
  private var timer: Timer?
  private var refreshTask: Task<Void, Never>?
  private var state = AppState()
  private var lastSuccessfulAgentData: [AgentKind: AgentRawData] = [:]
  private var lastUsageDataFingerprints: [AgentKind: UsageDataFingerprint] = [:]
  private let runtimeMode = AppRuntimeMode.current()
  private let loginItemManager = LoginItemManager()
  private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: self,
    userDriverDelegate: self
  )
  private var startAtLoginViewState = StartAtLoginViewState.make(status: .notRegistered)
  private var softwareUpdateViewState = SoftwareUpdateViewState.idle

  func applicationDidFinishLaunching(_ notification: Notification) {
    if runtimeMode == .live {
      _ = updaterController
    }

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem

    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    if runtimeMode == .demo {
      applyDemoState()
      startAtLoginViewState = .make(status: .enabled)
    } else {
      startAtLoginViewState = loginItemManager.configureOnLaunch()
      rescheduleRefreshTimer()
    }
    renderTitle()
    if runtimeMode == .live {
      refreshUsage()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    timer = nil
    refreshTask?.cancel()
    refreshTask = nil
    UsageFetcher.cancelActiveHelper()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if runtimeMode == .demo {
      applyDemoState()
      renderTitle()
    }
    rebuildMenu(menu)
  }

  @objc
  private func refreshTimerFired() {
    guard runtimeMode == .live else {
      return
    }

    rescheduleRefreshTimer()
    refreshUsage()
  }

  @objc
  private func refreshMenuItemSelected() {
    guard runtimeMode == .live else {
      applyDemoState()
      renderTitle()
      refreshMenuIfNeeded()
      return
    }

    rescheduleRefreshTimer()
    refreshUsage()
  }

  @objc
  private func startAtLoginMenuItemSelected(_ sender: NSMenuItem) {
    guard runtimeMode == .live else {
      startAtLoginViewState = .make(status: sender.state == .on ? .notRegistered : .enabled)
      refreshMenuIfNeeded()
      return
    }

    let shouldEnable = sender.state != .on
    startAtLoginViewState = loginItemManager.setEnabled(shouldEnable)
    refreshMenuIfNeeded()
  }

  @objc
  private func checkForUpdatesMenuItemSelected(_ sender: NSMenuItem) {
    guard runtimeMode == .live else {
      return
    }

    updaterController.checkForUpdates(sender)
  }

  @objc
  private func quitMenuItemSelected() {
    NSApplication.shared.terminate(nil)
  }

  private func rescheduleRefreshTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(
      timeInterval: currentRefreshInterval(),
      target: self,
      selector: #selector(refreshTimerFired),
      userInfo: nil,
      repeats: false
    )
  }

  private func currentRefreshInterval() -> TimeInterval {
    PowerSource.isOnBatteryPower() ? batteryRefreshInterval : pluggedInRefreshInterval
  }

  private func refreshUsage() {
    guard runtimeMode == .live else {
      applyDemoState()
      renderTitle()
      refreshMenuIfNeeded()
      return
    }

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
      defer {
        refreshTask = nil
      }

      let usageDataScan = await Task.detached(priority: .utility) {
        UsageDataScanner.currentScan()
      }.value

      let agentsToRefresh = UsageRefreshController.agentsNeedingRefresh(
        pricingMode: request.pricingMode,
        currentUsageDataScan: usageDataScan,
        cachedUsageDataFingerprints: lastUsageDataFingerprints,
        cachedAgentData: lastSuccessfulAgentData,
        lastErrorByAgent: state.lastErrorByAgent
      )

      var nextErrorByAgent = state.lastErrorByAgent
      for agent in agentsToRefresh {
        do {
          let snapshot = try await UsageFetcher.fetchUsage(
            offline: request.pricingMode == .offline,
            agents: [agent]
          )
          cache(snapshot: snapshot, usageDataScan: usageDataScan)
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

      applyRefreshSuccess(
        cachedSnapshot(),
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

  private func applyDemoState(now: Date = Date()) {
    state = DemoFixtures.appState(now: now)
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
