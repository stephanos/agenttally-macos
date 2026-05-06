import AppKit
import Foundation

private final class MenuRendererTarget: NSObject {
  @objc func handleMenuAction(_ sender: Any?) {}
}

@MainActor
func testMenuRenderer() throws {
  let menu = NSMenu()
  let target = MenuRendererTarget()
  let rows: [MenuRow] = [
    .submenu(
      title: "Refresh rate",
      rows: [
        .submenu(
          title: "Slow refreshes",
          rows: [
            .action(
              title: "Refresh every 5 min",
              kind: .refreshInterval(.fiveMinutes),
              keyEquivalent: "",
              state: .on
            )
          ]
        )
      ]
    )
  ]

  MenuRenderer.render(
    menu: menu,
    rows: rows,
    target: target,
    selectorProvider: { _ in #selector(MenuRendererTarget.handleMenuAction(_:)) }
  )

  guard let item = menu.items.first else {
    throw TestFailure(description: "renderer should create a parent submenu item")
  }

  try expect(item.title == "Refresh rate", "renderer should preserve the submenu title")
  guard let nestedSubmenu = item.submenu?.items.first?.submenu else {
    throw TestFailure(description: "renderer should create a nested submenu")
  }
  try expect(
    nestedSubmenu.title == "Slow refreshes",
    "renderer should preserve nested submenu titles"
  )
  try expect(
    nestedSubmenu.items.count == 1,
    "renderer should attach nested submenu children"
  )

  let childAction = nestedSubmenu.items.first?.representedObject as? MenuActionKind
  try expect(
    childAction == .refreshInterval(.fiveMinutes),
    "nested submenu leaf items should carry the refresh interval action on representedObject"
  )
}
