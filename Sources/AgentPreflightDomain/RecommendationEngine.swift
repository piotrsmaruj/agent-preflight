import Foundation

/// Picks the provider that keeps the largest reserve above the task-size policy.
///
/// A provider is safe when every quota window still holds at least the reserve the policy
/// requires for the task size. Between two safe providers the winner is the one with the
/// larger minimum ratio of remaining quota to required reserve; margins closer together
/// than the policy tolerance are reported as neutral.
public struct RecommendationEngine: Sendable {
  private let policy: TaskSizePolicy

  public init(policy: TaskSizePolicy = .default) {
    self.policy = policy
  }

  public func recommend(
    taskSize: TaskSize,
    snapshots: [ProviderIdentifier: QuotaSnapshot],
    staleProviders: Set<ProviderIdentifier>,
    now: Date
  ) -> Recommendation {
    guard staleProviders.isEmpty,
      let codex = assess(.codex, snapshots: snapshots, taskSize: taskSize, now: now),
      let claude = assess(.claudeCode, snapshots: snapshots, taskSize: taskSize, now: now)
    else {
      return unavailable()
    }
    return decide(codex, claude)
  }

  private func assess(
    _ provider: ProviderIdentifier,
    snapshots: [ProviderIdentifier: QuotaSnapshot],
    taskSize: TaskSize,
    now: Date
  ) -> Assessment? {
    guard let snapshot = snapshots[provider],
      let short = snapshot.window(.short, validAt: now),
      let allModelsWeekly = snapshot.window(.weekly, validAt: now),
      let weekly = bindingWeekly(in: snapshot, allModels: allModelsWeekly, now: now),
      let shortReset = short.resetsAt,
      let weeklyReset = weekly.resetsAt
    else { return nil }
    let required = policy.requirement(for: taskSize)
    let failures = [
      failure(provider, window: short, required: required.short, resetsAt: shortReset),
      failure(provider, window: weekly, required: required.weekly, resetsAt: weeklyReset),
    ].compactMap { $0 }
    let margin = min(
      short.remaining.value / required.short,
      weekly.remaining.value / required.weekly
    )
    return Assessment(provider: provider, margin: margin, failures: failures)
  }

  /// Returns the weekly window the task must fit into: the more constraining of the all-models
  /// week and a model-scoped week, or nil when a reported scoped week is unknown or expired.
  ///
  /// A present but unusable scoped week is as disqualifying as a missing required window, because
  /// the provider may already meter the task against a limit the app cannot see.
  private func bindingWeekly(
    in snapshot: QuotaSnapshot,
    allModels: QuotaWindow,
    now: Date
  ) -> QuotaWindow? {
    guard snapshot.windows[.modelWeekly] != nil else { return allModels }
    guard let scoped = snapshot.window(.modelWeekly, validAt: now) else { return nil }
    return scoped.remaining.value < allModels.remaining.value ? scoped : allModels
  }

  private func failure(
    _ provider: ProviderIdentifier,
    window: QuotaWindow,
    required: Double,
    resetsAt: Date
  ) -> ConstraintFailure? {
    guard window.remaining.value < required else { return nil }
    return ConstraintFailure(
      provider: provider,
      window: window.kind,
      remaining: window.remaining.value,
      required: required,
      resetsAt: resetsAt,
      scopeLabel: window.scopeLabel
    )
  }

  private func decide(_ first: Assessment, _ second: Assessment) -> Recommendation {
    if first.isSafe != second.isSafe {
      let winner = first.isSafe ? first.provider : second.provider
      return Recommendation(
        decision: .provider(winner),
        reason: .onlySafe(winner),
        failures: [],
        nearestRelevantReset: nil
      )
    }
    guard first.isSafe else { return noSafeChoice(first.failures + second.failures) }
    guard abs(first.margin - second.margin) >= policy.neutralTolerance else {
      return Recommendation(
        decision: .neutral,
        reason: .marginsWithinTolerance,
        failures: [],
        nearestRelevantReset: nil
      )
    }
    let winner = first.margin > second.margin ? first.provider : second.provider
    return Recommendation(
      decision: .provider(winner),
      reason: .largerMargin(winner),
      failures: [],
      nearestRelevantReset: nil
    )
  }

  private func noSafeChoice(_ failures: [ConstraintFailure]) -> Recommendation {
    Recommendation(
      decision: .noSafeChoice,
      reason: .insufficientQuota,
      failures: failures,
      nearestRelevantReset: failures.map(\.resetsAt).min()
    )
  }

  private func unavailable() -> Recommendation {
    Recommendation(
      decision: .unavailable,
      reason: .incompleteOrStaleData,
      failures: [],
      nearestRelevantReset: nil
    )
  }

  private struct Assessment {
    let provider: ProviderIdentifier
    let margin: Double
    let failures: [ConstraintFailure]

    var isSafe: Bool { failures.isEmpty }
  }
}
