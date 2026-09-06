// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AgentPreflight",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "AgentPreflightDomain", targets: ["AgentPreflightDomain"]),
    .library(name: "AgentPreflightApplication", targets: ["AgentPreflightApplication"]),
    .library(name: "AgentPreflightInfrastructure", targets: ["AgentPreflightInfrastructure"]),
  ],
  targets: [
    .target(name: "AgentPreflightDomain"),
    .target(
      name: "AgentPreflightApplication",
      dependencies: ["AgentPreflightDomain"]
    ),
    .target(
      name: "AgentPreflightInfrastructure",
      dependencies: ["AgentPreflightDomain", "AgentPreflightApplication"],
      linkerSettings: [.linkedFramework("Security")]
    ),
    .testTarget(
      name: "AgentPreflightDomainTests",
      dependencies: ["AgentPreflightDomain"]
    ),
    .testTarget(
      name: "AgentPreflightApplicationTests",
      dependencies: ["AgentPreflightDomain", "AgentPreflightApplication"]
    ),
    .testTarget(
      name: "AgentPreflightInfrastructureTests",
      dependencies: [
        "AgentPreflightDomain", "AgentPreflightApplication", "AgentPreflightInfrastructure",
      ],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
