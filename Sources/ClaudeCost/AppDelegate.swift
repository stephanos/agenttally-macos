import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let refreshInterval: TimeInterval = 60

  private var statusItem: NSStatusItem?
  private var timer: Timer?
  private var state = AppState()
  private let loginItemManager = LoginItemManager()
  private var startAtLoginViewState = StartAtLoginViewState.make(status: .notRegistered)

  func applicationDidFinishLaunching(_ notification: Notification) {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem

    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    timer = Timer.scheduledTimer(
      timeInterval: refreshInterval,
      target: self,
      selector: #selector(refreshTimerFired),
      userInfo: nil,
      repeats: true
    )

    startAtLoginViewState = loginItemManager.configureOnLaunch()
    renderTitle()
    refreshUsage()
  }

  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    timer = nil
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    rebuildMenu(menu)
  }

  @objc
  private func refreshTimerFired() {
    refreshUsage()
  }

  @objc
  private func refreshMenuItemSelected() {
    refreshUsage()
  }

  @objc
  private func startAtLoginMenuItemSelected(_ sender: NSMenuItem) {
    let shouldEnable = sender.state != .on
    startAtLoginViewState = loginItemManager.setEnabled(shouldEnable)
    refreshMenuIfNeeded()
  }

  @objc
  private func quitMenuItemSelected() {
    NSApplication.shared.terminate(nil)
  }

  private func refreshUsage() {
    guard let nextState = UsageRefreshController.beginRefresh(from: state) else {
      return
    }

    state = nextState
    renderTitle()

    Task {
      do {
        let snapshot = try await UsageFetcher.fetchUsage()
        applyRefreshSuccess(snapshot)
      } catch {
        applyRefreshFailure(error)
      }
    }
  }

  private func applyRefreshSuccess(_ snapshot: UsageSnapshot) {
    state = UsageRefreshController.applySuccess(snapshot: snapshot, to: state)
    renderTitle()
    refreshMenuIfNeeded()
  }

  private func applyRefreshFailure(_ error: Error) {
    state = UsageRefreshController.applyFailure(error: error, to: state)
    renderTitle()
    if let lastError = state.lastError, !lastError.isEmpty {
      NSLog("claudecost refresh failed: %@", lastError)
    }
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
    case .quit:
      return #selector(quitMenuItemSelected)
    }
  }
}
