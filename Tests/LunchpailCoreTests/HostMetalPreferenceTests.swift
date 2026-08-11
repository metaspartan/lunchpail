import Foundation
import Testing

@testable import LunchpailCore

@Test func readsAbsentPreference() throws {
  let runner = StubRunner { _, arguments, _ in
    #expect(arguments.prefix(2) == ["read", HostMetalPreferenceManager.domain])
    return CommandResult(
      status: 1,
      stdout: "",
      stderr: "The domain/default pair does not exist"
    )
  }
  let manager = HostMetalPreferenceManager(
    runner: runner,
    backupURL: temporaryBackupURL()
  )
  #expect(try manager.read() == .absent)
}

@Test func readsAbsentPreferenceWhenDomainExistsWithoutKey() throws {
  let runner = StubRunner { _, _, _ in
    CommandResult(
      status: 1,
      stdout: "",
      stderr: "Could not find key 'ForceUnrestrictedDeviceFeatureLevel' in domain."
    )
  }
  let manager = HostMetalPreferenceManager(runner: runner, backupURL: temporaryBackupURL())
  #expect(try manager.read() == .absent)
}

@Test func enableAndRestoreAreJournaled() throws {
  let state = PreferenceStubState()
  let runner = StubRunner { _, arguments, _ in state.run(arguments: arguments) }
  let backupURL = temporaryBackupURL()
  defer { try? FileManager.default.removeItem(at: backupURL.deletingLastPathComponent()) }
  let manager = HostMetalPreferenceManager(runner: runner, backupURL: backupURL)

  let previous = try manager.enable()
  #expect(previous == .absent)
  #expect(manager.hasPendingBackup)
  #expect(state.value == true)

  let restored = try manager.restore()
  #expect(restored == .absent)
  #expect(!manager.hasPendingBackup)
  #expect(state.value == nil)
}

@Test func concurrentEnableMutatesOnce() async throws {
  let state = PreferenceStubState()
  let runner = StubRunner { _, arguments, _ in state.run(arguments: arguments) }
  let backupURL = temporaryBackupURL()
  defer { try? FileManager.default.removeItem(at: backupURL.deletingLastPathComponent()) }
  let manager = HostMetalPreferenceManager(runner: runner, backupURL: backupURL)

  let outcomes = await withTaskGroup(of: String.self) { group in
    for _ in 0..<2 {
      group.addTask {
        do {
          _ = try manager.enable()
          return "enabled"
        } catch HostMetalPreferenceError.backupAlreadyExists {
          return "already-enabled"
        } catch {
          return "unexpected: \(error.localizedDescription)"
        }
      }
    }
    var values: [String] = []
    for await value in group {
      values.append(value)
    }
    return values
  }

  #expect(outcomes.filter { $0 == "enabled" }.count == 1)
  #expect(outcomes.filter { $0 == "already-enabled" }.count == 1)
  #expect(state.value == true)
  _ = try manager.restore()
}

private struct StubRunner: CommandRunning {
  let handler: @Sendable (URL, [String], [String: String]?) throws -> CommandResult

  init(
    _ handler: @escaping @Sendable (URL, [String], [String: String]?) throws -> CommandResult
  ) {
    self.handler = handler
  }

  func run(
    executable: URL,
    arguments: [String],
    environment: [String: String]?
  ) throws -> CommandResult {
    try handler(executable, arguments, environment)
  }
}

private final class PreferenceStubState: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Bool?

  var value: Bool? {
    lock.withLock { storedValue }
  }

  func run(arguments: [String]) -> CommandResult {
    lock.withLock {
      switch arguments.first {
      case "read":
        guard let storedValue else {
          return CommandResult(status: 1, stdout: "", stderr: "does not exist")
        }
        return CommandResult(status: 0, stdout: storedValue ? "1\n" : "0\n", stderr: "")
      case "write":
        storedValue = arguments.last == "true"
        return CommandResult(status: 0, stdout: "", stderr: "")
      case "delete":
        storedValue = nil
        return CommandResult(status: 0, stdout: "", stderr: "")
      default:
        return CommandResult(status: 2, stdout: "", stderr: "unexpected arguments")
      }
    }
  }
}

private func temporaryBackupURL() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-tests-\(UUID().uuidString)")
    .appendingPathComponent("state.json")
}
