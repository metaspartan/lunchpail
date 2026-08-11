import Foundation

public struct CommandResult: Sendable, Equatable {
  public let status: Int32
  public let stdout: String
  public let stderr: String

  public init(status: Int32, stdout: String, stderr: String) {
    self.status = status
    self.stdout = stdout
    self.stderr = stderr
  }
}

public struct CommandFailure: LocalizedError, Sendable {
  public let executable: String
  public let arguments: [String]
  public let result: CommandResult

  public var errorDescription: String? {
    let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    return detail.isEmpty
      ? "\(executable) exited with status \(result.status)"
      : "\(executable) exited with status \(result.status): \(detail)"
  }
}

public protocol CommandRunning: Sendable {
  func run(
    executable: URL,
    arguments: [String],
    environment: [String: String]?
  ) throws -> CommandResult
}

public struct CommandRunner: CommandRunning, Sendable {
  public init() {}

  public func run(
    executable: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil
  ) throws -> CommandResult {
    let process = Process()
    let stdoutCapture = try TemporaryCaptureFile(suffix: "stdout")
    let stderrCapture = try TemporaryCaptureFile(suffix: "stderr")
    defer {
      stdoutCapture.remove()
      stderrCapture.remove()
    }

    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = stdoutCapture.handle
    process.standardError = stderrCapture.handle
    if let environment {
      process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new
      }
    }

    try process.run()
    process.waitUntilExit()
    try stdoutCapture.handle.close()
    try stderrCapture.handle.close()

    let output = try Data(contentsOf: stdoutCapture.url)
    let error = try Data(contentsOf: stderrCapture.url)
    return CommandResult(
      status: process.terminationStatus,
      stdout: String(decoding: output, as: UTF8.self),
      stderr: String(decoding: error, as: UTF8.self)
    )
  }

  @discardableResult
  public func checkedRun(
    executable: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil
  ) throws -> CommandResult {
    let result = try run(executable: executable, arguments: arguments, environment: environment)
    guard result.status == 0 else {
      throw CommandFailure(
        executable: executable.path,
        arguments: arguments,
        result: result
      )
    }
    return result
  }
}

private final class TemporaryCaptureFile {
  let url: URL
  let handle: FileHandle

  init(suffix: String) throws {
    let directory = FileManager.default.temporaryDirectory
    url = directory.appendingPathComponent("lunchpail-\(UUID().uuidString).\(suffix)")
    guard
      FileManager.default.createFile(
        atPath: url.path,
        contents: nil,
        attributes: [.posixPermissions: 0o600]
      )
    else {
      throw CocoaError(.fileWriteUnknown)
    }
    do {
      handle = try FileHandle(forWritingTo: url)
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }

  func remove() {
    try? handle.close()
    try? FileManager.default.removeItem(at: url)
  }
}
