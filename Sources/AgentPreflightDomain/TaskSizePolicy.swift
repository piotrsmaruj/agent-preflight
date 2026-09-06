public enum TaskSize: String, CaseIterable, Codable, Sendable {
  case small
  case medium
  case large
}

public struct ReserveRequirement: Equatable, Sendable {
  public let short: Double
  public let weekly: Double

  public init(short: Double, weekly: Double) {
    self.short = short
    self.weekly = weekly
  }
}

public struct TaskSizePolicy: Equatable, Sendable {
  public let small: ReserveRequirement
  public let medium: ReserveRequirement
  public let large: ReserveRequirement
  public let neutralTolerance: Double

  public init(
    small: ReserveRequirement,
    medium: ReserveRequirement,
    large: ReserveRequirement,
    neutralTolerance: Double
  ) {
    self.small = small
    self.medium = medium
    self.large = large
    self.neutralTolerance = neutralTolerance
  }

  public static let `default` = Self(
    small: ReserveRequirement(short: 15, weekly: 5),
    medium: ReserveRequirement(short: 35, weekly: 10),
    large: ReserveRequirement(short: 60, weekly: 20),
    neutralTolerance: 0.10
  )

  public func requirement(for size: TaskSize) -> ReserveRequirement {
    switch size {
    case .small: small
    case .medium: medium
    case .large: large
    }
  }
}
