// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ClaudeCost",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "ClaudeCost",
      targets: ["ClaudeCost"]
    )
  ],
  targets: [
    .executableTarget(
      name: "ClaudeCost"
    )
  ]
)
