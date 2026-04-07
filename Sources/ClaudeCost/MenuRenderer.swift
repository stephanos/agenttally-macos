import AppKit

@MainActor
enum MenuRenderer {
  static func render(
    menu: NSMenu,
    rows: [MenuRow],
    target: AnyObject,
    selectorProvider: (MenuActionKind) -> Selector
  ) {
    menu.removeAllItems()

    for row in rows {
      menu.addItem(makeMenuItem(for: row, target: target, selectorProvider: selectorProvider))
    }
  }

  private static func makeMenuItem(
    for row: MenuRow,
    target: AnyObject,
    selectorProvider: (MenuActionKind) -> Selector
  ) -> NSMenuItem {
    switch row {
    case .disabled(let title):
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.isEnabled = false
      return item
    case .separator:
      return .separator()
    case .action(let title, let kind, let keyEquivalent, let state):
      let item = NSMenuItem(
        title: title,
        action: selectorProvider(kind),
        keyEquivalent: keyEquivalent
      )
      item.target = target
      item.state = nsControlState(for: state)
      return item
    }
  }

  private static func nsControlState(for state: MenuCheckState) -> NSControl.StateValue {
    switch state {
    case .off:
      return .off
    case .on:
      return .on
    case .mixed:
      return .mixed
    }
  }
}
