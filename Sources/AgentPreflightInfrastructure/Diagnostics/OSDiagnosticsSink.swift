import AgentPreflightApplication
import OSLog

public actor OSDiagnosticsSink: DiagnosticsSink {
  private let logger: Logger

  public init(subsystem: String = "com.agentpreflight.app", category: String = "runtime") {
    self.logger = Logger(subsystem: subsystem, category: category)
  }

  public func record(_ event: DiagnosticEvent) async {
    logger.error("\(event.description, privacy: .public)")
  }
}
