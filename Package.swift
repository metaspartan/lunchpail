// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Lunchpail",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "lunchpail", targets: ["LunchpailCLI"]),
    .executable(name: "LunchpailApp", targets: ["LunchpailApp"]),
    .library(name: "LunchpailCore", targets: ["LunchpailCore"]),
    .library(name: "LunchpailMetalShim", type: .dynamic, targets: ["LunchpailMetalShim"]),
    .executable(name: "lunchpail-metal-probe", targets: ["LunchpailMetalProbe"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.22.0"),
  ],
  targets: [
    .target(
      name: "LunchpailCore",
      linkerSettings: [
        .linkedFramework("Metal"),
        .linkedFramework("Security"),
        .linkedFramework("Virtualization"),
      ]
    ),
    .executableTarget(
      name: "LunchpailCLI",
      dependencies: [
        "LunchpailAPI",
        "LunchpailCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .target(
      name: "LunchpailAPI",
      dependencies: [
        "LunchpailCore",
        .product(name: "Hummingbird", package: "hummingbird"),
      ],
      resources: [.copy("Resources/openapi.yaml")]
    ),
    .executableTarget(
      name: "LunchpailApp",
      dependencies: ["LunchpailCore"]
    ),
    .target(
      name: "LunchpailMetalShim",
      path: "Guest/MetalShim",
      publicHeadersPath: "include",
      cSettings: [
        .unsafeFlags(["-fobjc-arc", "-fvisibility=hidden"])
      ],
      linkerSettings: [
        .linkedFramework("Foundation"),
        .linkedFramework("Metal"),
      ]
    ),
    .executableTarget(
      name: "LunchpailMetalProbe",
      path: "Guest/MetalProbe",
      linkerSettings: [
        .linkedFramework("Foundation"),
        .linkedFramework("Metal"),
      ]
    ),
    .testTarget(name: "LunchpailCoreTests", dependencies: ["LunchpailCore"]),
    .testTarget(name: "LunchpailAPITests", dependencies: ["LunchpailAPI"]),
  ]
)
