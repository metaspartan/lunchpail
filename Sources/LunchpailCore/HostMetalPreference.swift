import Darwin
import Foundation

public struct HostMetalPreference: Codable, Equatable, Sendable {
  public let isSet: Bool
  public let enabled: Bool?
  public let rawValue: String?

  public init(isSet: Bool, enabled: Bool?, rawValue: String?) {
    self.isSet = isSet
    self.enabled = enabled
    self.rawValue = rawValue
  }

  public static let absent = HostMetalPreference(isSet: false, enabled: nil, rawValue: nil)

  public var description: String {
    guard isSet else { return "not set (stock)" }
    if let enabled { return enabled ? "enabled" : "disabled" }
    return "set to unrecognized value \(rawValue ?? "<unknown>")"
  }
}

public enum HostMetalPreferenceError: LocalizedError, Equatable {
  case backupAlreadyExists(String)
  case noBackup(String)
  case unrecognizedExistingValue(String)
  case cannotLock(String)

  public var errorDescription: String? {
    switch self {
    case .backupAlreadyExists(let path):
      return
        "a Metal host-preference backup already exists at \(path); restore it before enabling again"
    case .noBackup(let path):
      return "no Metal host-preference backup exists at \(path)"
    case .unrecognizedExistingValue(let value):
      return "refusing to replace an unrecognized existing host preference: \(value)"
    case .cannotLock(let path):
      return "could not lock Metal host-preference state: \(path)"
    }
  }
}

public struct HostMetalPreferenceManager: Sendable {
  public static let domain = "com.apple.gpusw.ParavirtualizedGraphics"
  public static let key = "ForceUnrestrictedDeviceFeatureLevel"

  private let runner: any CommandRunning
  public let backupURL: URL

  public init(
    runner: any CommandRunning = CommandRunner(),
    backupURL: URL? = nil
  ) {
    self.runner = runner
    self.backupURL =
      backupURL
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".lunchpail/state/metal-host-preference.json")
  }

  public func read() throws -> HostMetalPreference {
    let result = try runner.run(
      executable: URL(fileURLWithPath: "/usr/bin/defaults"),
      arguments: ["read", Self.domain, Self.key],
      environment: nil
    )
    guard result.status == 0 else {
      let combined = result.stderr + result.stdout
      if Self.isMissingPreferenceMessage(combined) {
        return .absent
      }
      throw CommandFailure(
        executable: "/usr/bin/defaults",
        arguments: ["read", Self.domain, Self.key],
        result: result
      )
    }

    let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    switch raw.lowercased() {
    case "1", "true", "yes":
      return HostMetalPreference(isSet: true, enabled: true, rawValue: raw)
    case "0", "false", "no":
      return HostMetalPreference(isSet: true, enabled: false, rawValue: raw)
    default:
      return HostMetalPreference(isSet: true, enabled: nil, rawValue: raw)
    }
  }

  public func enable() throws -> HostMetalPreference {
    try withMutationLock { try enableLocked() }
  }

  @discardableResult
  public func restore() throws -> HostMetalPreference {
    try withMutationLock { try restoreLocked() }
  }

  public var hasPendingBackup: Bool {
    FileManager.default.fileExists(atPath: backupURL.path)
  }

  private func enableLocked() throws -> HostMetalPreference {
    guard !FileManager.default.fileExists(atPath: backupURL.path) else {
      throw HostMetalPreferenceError.backupAlreadyExists(backupURL.path)
    }

    let previous = try read()
    if previous.isSet && previous.enabled == nil {
      throw HostMetalPreferenceError.unrecognizedExistingValue(previous.rawValue ?? "<unknown>")
    }

    try FileManager.default.createDirectory(
      at: backupURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder.stable.encode(previous)
    try data.write(to: backupURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: backupURL.path
    )

    do {
      let result = try runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/defaults"),
        arguments: ["write", Self.domain, Self.key, "-bool", "true"],
        environment: nil
      )
      guard result.status == 0 else {
        throw CommandFailure(
          executable: "/usr/bin/defaults",
          arguments: ["write", Self.domain, Self.key, "-bool", "true"],
          result: result
        )
      }
    } catch {
      try? FileManager.default.removeItem(at: backupURL)
      throw error
    }

    return previous
  }

  private func restoreLocked() throws -> HostMetalPreference {
    guard FileManager.default.fileExists(atPath: backupURL.path) else {
      throw HostMetalPreferenceError.noBackup(backupURL.path)
    }
    let previous = try JSONDecoder().decode(
      HostMetalPreference.self,
      from: Data(contentsOf: backupURL)
    )

    let arguments: [String]
    if previous.isSet, let enabled = previous.enabled {
      arguments = ["write", Self.domain, Self.key, "-bool", enabled ? "true" : "false"]
    } else {
      arguments = ["delete", Self.domain, Self.key]
    }

    let result = try runner.run(
      executable: URL(fileURLWithPath: "/usr/bin/defaults"),
      arguments: arguments,
      environment: nil
    )
    if result.status != 0 {
      let combined = result.stderr + result.stdout
      let deletingAlreadyAbsent =
        !previous.isSet
        && Self.isMissingPreferenceMessage(combined)
      guard deletingAlreadyAbsent else {
        throw CommandFailure(
          executable: "/usr/bin/defaults",
          arguments: arguments,
          result: result
        )
      }
    }

    try FileManager.default.removeItem(at: backupURL)
    return previous
  }

  private func withMutationLock<T>(_ operation: () throws -> T) throws -> T {
    let directory = backupURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let lockURL = backupURL.appendingPathExtension("lock")
    let descriptor = lockURL.path.withCString {
      Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
      throw HostMetalPreferenceError.cannotLock(lockURL.path)
    }
    defer { Darwin.close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else {
      throw HostMetalPreferenceError.cannotLock(lockURL.path)
    }
    defer { flock(descriptor, LOCK_UN) }
    return try operation()
  }

  private static func isMissingPreferenceMessage(_ message: String) -> Bool {
    message.localizedCaseInsensitiveContains("does not exist")
      || message.localizedCaseInsensitiveContains("not found")
      || message.localizedCaseInsensitiveContains("could not find key")
  }
}

extension JSONEncoder {
  public static var stable: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}
