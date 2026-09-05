// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AgentPreflight",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "AgentPreflightDomain", targets: ["AgentPreflightDomain"])
  ],
  targets: [
    .target(name: "AgentPreflightDomain"),
    .testTarget(
      name: "AgentPreflightDomainTests",
      dependencies: ["AgentPreflightDomain"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
