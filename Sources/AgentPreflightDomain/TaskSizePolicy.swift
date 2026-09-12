public enum TaskSize: String, CaseIterable, Codable, Sendable {
  case small
  case medium
  case large
}

public enum TaskSizePolicyError: Error, Equatable, Sendable {
  case reserveOutOfRange(Double)
  case neutralToleranceOutOfRange(Double)
}

/// The quota a task of one size must leave untouched in each window.
///
/// A reserve is a percentage and must stay above zero: the recommendation divides remaining quota
/// by the required reserve, so a zero reserve would make every provider infinitely safe and
/// silently disable the comparison the app exists to make.
public struct ReserveRequirement: Equatable, Codable, Sendable {
  public static let allowedPercentages: ClosedRange<Double> = 1...100
  public let short: Double
  public let weekly: Double

  public init(short: Double, weekly: Double) throws {
    self.short = try Self.validated(short)
    self.weekly = try Self.validated(weekly)
  }

  private static func validated(_ percentage: Double) throws -> Double {
    guard percentage.isFinite, allowedPercentages.contains(percentage) else {
      throw TaskSizePolicyError.reserveOutOfRange(percentage)
    }
    return percentage
  }

  private enum CodingKeys: String, CodingKey { case short, weekly }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      short: container.decode(Double.self, forKey: .short),
      weekly: container.decode(Double.self, forKey: .weekly)
    )
  }
}

/// The reserves and tie tolerance the recommendation applies, editable in Settings.
///
/// `neutralTolerance` compares two providers' minimum margins, each a ratio of remaining quota to
/// the required reserve. A tolerance of `1` already calls a doubled margin a tie, so larger values
/// would report every comparison as neutral and are rejected.
public struct TaskSizePolicy: Equatable, Codable, Sendable {
  public static let allowedNeutralTolerances: ClosedRange<Double> = 0...1
  public let small: ReserveRequirement
  public let medium: ReserveRequirement
  public let large: ReserveRequirement
  public let neutralTolerance: Double

  public init(
    small: ReserveRequirement,
    medium: ReserveRequirement,
    large: ReserveRequirement,
    neutralTolerance: Double
  ) throws {
    guard neutralTolerance.isFinite,
      Self.allowedNeutralTolerances.contains(neutralTolerance)
    else {
      throw TaskSizePolicyError.neutralToleranceOutOfRange(neutralTolerance)
    }
    self.small = small
    self.medium = medium
    self.large = large
    self.neutralTolerance = neutralTolerance
  }

  /// The documented reserves a fresh install starts from and Settings restores.
  ///
  /// Force-unwrapping the validation is safe only because every literal below is inside the
  /// allowed ranges; a future edit that leaves them traps here rather than shipping a policy the
  /// engine cannot use.
  public static let `default`: Self = {
    guard
      let policy = try? Self(
        small: ReserveRequirement(short: 15, weekly: 5),
        medium: ReserveRequirement(short: 35, weekly: 10),
        large: ReserveRequirement(short: 60, weekly: 20),
        neutralTolerance: 0.10
      )
    else { preconditionFailure("The built-in task size policy must satisfy its own ranges.") }
    return policy
  }()

  public func requirement(for size: TaskSize) -> ReserveRequirement {
    switch size {
    case .small: small
    case .medium: medium
    case .large: large
    }
  }

  private enum CodingKeys: String, CodingKey { case small, medium, large, neutralTolerance }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      small: container.decode(ReserveRequirement.self, forKey: .small),
      medium: container.decode(ReserveRequirement.self, forKey: .medium),
      large: container.decode(ReserveRequirement.self, forKey: .large),
      neutralTolerance: container.decode(Double.self, forKey: .neutralTolerance)
    )
  }
}
