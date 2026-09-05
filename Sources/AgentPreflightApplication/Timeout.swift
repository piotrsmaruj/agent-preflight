import Foundation

public func withTimeout<Value: Sendable>(
  seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
  try await withThrowingTaskGroup(of: Value.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: .seconds(seconds))
      throw ProviderFailure.timeout
    }
    defer { group.cancelAll() }
    guard let value = try await group.next() else { throw ProviderFailure.timeout }
    return value
  }
}
