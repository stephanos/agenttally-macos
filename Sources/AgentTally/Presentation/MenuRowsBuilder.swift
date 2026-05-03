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
      .disabled("Last refreshed: \(StatusPresenter.lastRefreshedLabel(for: state, now: now))"),
    ]

    if state.isRefreshing {
      rows.append(.disabled("Refreshing ..."))
    } else {
      rows.append(.action(title: "Refresh", kind: .refresh, keyEquivalent: "", state: .off))
    }

    rows.append(.separator)

    if state.lastRefreshAt != nil {
      var isFirst = true
      var renderedAgents = Set<AgentKind>()
      for spending in state.agentSpendings {
        if !isFirst { rows.append(.separator) }
        isFirst = false

        let agent = AgentKind(displayName: spending.name)
        if let agent {
          renderedAgents.insert(agent)
        }

        if spending.isInstalled {
          rows.append(.section("\(spending.name) spending"))
          rows.append(
            .disabled("Today: $\(StatusPresenter.displayDollarAmount(for: spending.todayCost))"))
          rows.append(
            .disabled(
              "Month: $\(StatusPresenter.displayDollarAmount(for: spending.monthCost)) (\(state.businessDays) biz days)"
            )
          )
          rows.append(
            .disabled("Avg/Day: $\(StatusPresenter.displayDollarAmount(for: spending.avgPerDay))")
          )
          rows.append(
            .disabled(
              "Last usage: \(StatusPresenter.lastUsageDetectedLabel(for: spending.lastUsageDetectedAt, now: now))"
            )
          )
        } else if !spending.isInstalled {
          rows.append(.disabled("\(spending.name): not installed"))
        }

        if let agent, let error = state.lastErrorByAgent[agent], !error.isEmpty {
          rows.append(.disabled("Error: \(error)"))
        }
      }

      for agent in AgentKind.allCases where !renderedAgents.contains(agent) {
        guard let error = state.lastErrorByAgent[agent], !error.isEmpty else {
          continue
        }

        if !isFirst { rows.append(.separator) }
        isFirst = false
        rows.append(.section("\(agent.displayName) spending"))
        rows.append(.disabled("Error: \(error)"))
      }
    }

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
