import Foundation

public enum MenuCheckState: Equatable {
  case off
  case on
  case mixed
}

public enum MenuActionKind: Equatable {
  case startAtLogin
  case refresh
  case quit
}

public enum MenuRow: Equatable {
  case disabled(String)
  case section(String)
  case separator
  case action(title: String, kind: MenuActionKind, keyEquivalent: String, state: MenuCheckState)
}

public enum MenuRowsBuilder {
  public static func rows(
    for state: AppState,
    startAtLogin: StartAtLoginViewState,
    appVersion: String? = nil,
    now: Date = Date()
  ) -> [MenuRow] {
    var rows: [MenuRow] = [
      .disabled(headerTitle(appVersion: appVersion)),
      .separator,
    ]

    if state.lastRefreshAt != nil, state.lastError == nil {
      rows.append(.section("Claude Code spending"))
      rows.append(.disabled("Today: $\(StatusPresenter.displayDollarAmount(for: state.todayCost))"))
      rows.append(
        .disabled(
          "Month: $\(StatusPresenter.displayDollarAmount(for: state.monthCost)) (\(state.businessDays) biz days)"
        )
      )
      rows.append(
        .disabled("Avg/Day: $\(StatusPresenter.displayDollarAmount(for: state.avgPerDay))")
      )
    }

    if let lastError = state.lastError, !lastError.isEmpty {
      rows.append(.disabled("Error: \(lastError)"))
    }

    rows.append(
      .disabled("Last updated: \(StatusPresenter.lastUpdatedLabel(for: state, now: now))"))
    rows.append(.separator)
    rows.append(
      .action(
        title: "Open at Login",
        kind: .startAtLogin,
        keyEquivalent: "",
        state: startAtLogin.menuState
      )
    )

    if let message = startAtLogin.message, !message.isEmpty {
      rows.append(.disabled(message))
    }

    if state.isRefreshing {
      rows.append(.disabled("Refreshing ..."))
    } else {
      rows.append(.action(title: "Refresh", kind: .refresh, keyEquivalent: "", state: .off))
    }
    rows.append(.action(title: "Quit", kind: .quit, keyEquivalent: "q", state: .off))

    return rows
  }

  private static func headerTitle(appVersion: String?) -> String {
    guard let appVersion = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
      !appVersion.isEmpty
    else {
      return "AgentTally"
    }

    return "AgentTally v\(appVersion)"
  }
}
