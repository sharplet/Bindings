// swift-tools-version:5.10

import PackageDescription

let package = Package(
  name: "Bindings",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
  ],
  products: [
    .library(name: "Bindings", targets: ["Bindings"]),
    .library(name: "UIKitBindings", targets: ["UIKitBindings"]),
  ],
  targets: [
    .target(name: "Bindings"),
    .target(name: "UIKitBindings", dependencies: ["Bindings"]),
  ]
)
