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
  case separator
  case action(title: String, kind: MenuActionKind, keyEquivalent: String, state: MenuCheckState)
}

public enum MenuRowsBuilder {
  public static func rows(
    for state: AppState,
    startAtLogin: StartAtLoginViewState,
    now: Date = Date()
  ) -> [MenuRow] {
    var rows: [MenuRow] = [
      .disabled("Claude Code spend"),
      .separator,
    ]

    if state.lastRefreshAt != nil, state.lastError == nil {
      rows.append(.disabled(String(format: "Today: $%.2f", state.todayCost)))
      rows.append(
        .disabled(
          String(
            format: "Month: $%.2f (%d biz days)",
            state.monthCost,
            state.businessDays
          )
        )
      )
      rows.append(.disabled(String(format: "Avg/Day: $%.2f", state.avgPerDay)))
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
}
