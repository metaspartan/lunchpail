import Foundation
import LunchpailCore

public enum VMRuntimePhase: String, Codable, Sendable {
  case stopped
  case starting
  case running
  case stopping
  case failed
}

public struct VMRuntimeStatus: Codable, Equatable, Sendable {
  public let vmID: String
  public let phase: VMRuntimePhase
  public let error: String?
}

@MainActor
public final class VMRuntimeService {
  private var sessions: [String: RuntimeSession] = [:]

  public init() {}

  public func statuses() -> [String: VMRuntimeStatus] {
    sessions.mapValues(\.status)
  }

  public func status(for vmID: String) -> VMRuntimeStatus {
    sessions[vmID]?.status ?? VMRuntimeStatus(vmID: vmID, phase: .stopped, error: nil)
  }

  public func start(_ entry: VMInventoryEntry) throws -> VMRuntimeStatus {
    guard entry.isValid else {
      throw VMRuntimeError.invalidVM(entry.validationError ?? "invalid manifest")
    }
    if entry.metalProfileID != MetalProfileRegistry.stock.id {
      let preference = try HostMetalPreferenceManager().read()
      guard preference.enabled == true else {
        throw VMRuntimeError.metalBridgeDisabled(entry.metalProfileID)
      }
    }
    if let existing = sessions[entry.id], existing.isActive {
      throw VMRuntimeError.alreadyRunning(entry.id)
    }

    let manifestURL = entry.manifestURL
    let lock = try VMDirectoryLock(
      directoryURL: manifestURL.deletingLastPathComponent(),
      mode: .exclusive
    )
    let configuration = try MacVMConfigurationBuilder.build(manifestURL: manifestURL)
    let runner = MacVMRunner(configuration: configuration)
    let session = RuntimeSession(vmID: entry.id, runner: runner, lock: lock)
    sessions[entry.id] = session
    session.task = Task { @MainActor [weak self, weak session] in
      guard let self, let session else { return }
      do {
        try await session.runner.start()
        session.phase = .running
        try await session.runner.waitForStop()
        session.phase = .stopped
      } catch {
        session.phase = .failed
        session.error = error.localizedDescription
      }
      session.releaseOwnership()
      self.sessions[entry.id] = session
    }
    return session.status
  }

  public func stop(vmID: String, force: Bool) async throws -> VMRuntimeStatus {
    guard let session = sessions[vmID], session.isActive else {
      throw VMRuntimeError.notRunning(vmID)
    }
    let previousPhase = session.phase
    session.phase = .stopping
    do {
      if force {
        try await session.runner.forceStop()
      } else {
        guard try session.runner.requestStop() else {
          throw VMRuntimeError.stopRejected(vmID)
        }
      }
    } catch {
      session.phase = previousPhase
      throw error
    }
    return session.status
  }

  public func shutdown(graceSeconds: Double = 10) async {
    let active = sessions.values.filter(\.isActive)
    for session in active {
      session.phase = .stopping
      _ = try? session.runner.requestStop()
    }
    let deadline = Date().addingTimeInterval(graceSeconds)
    while Date() < deadline && active.contains(where: \.isActive) {
      try? await Task.sleep(for: .milliseconds(100))
    }
    for session in active where session.isActive {
      try? await session.runner.forceStop()
    }
  }
}

@MainActor
private final class RuntimeSession {
  let vmID: String
  let runner: MacVMRunner
  var lock: VMDirectoryLock?
  var task: Task<Void, Never>?
  var phase: VMRuntimePhase = .starting
  var error: String?

  init(vmID: String, runner: MacVMRunner, lock: VMDirectoryLock) {
    self.vmID = vmID
    self.runner = runner
    self.lock = lock
  }

  var isActive: Bool {
    phase == .starting || phase == .running || phase == .stopping
  }

  var status: VMRuntimeStatus {
    VMRuntimeStatus(vmID: vmID, phase: phase, error: error)
  }

  func releaseOwnership() {
    lock = nil
    task = nil
  }
}

public enum VMRuntimeError: LocalizedError, Equatable {
  case invalidVM(String)
  case metalBridgeDisabled(String)
  case alreadyRunning(String)
  case notRunning(String)
  case stopRejected(String)

  public var errorDescription: String? {
    switch self {
    case .invalidVM(let detail): return "invalid VM: \(detail)"
    case .metalBridgeDisabled(let profile):
      return
        "Metal host bridge is disabled for profile \(profile); enable it explicitly before starting the VM"
    case .alreadyRunning(let id): return "VM is already running: \(id)"
    case .notRunning(let id): return "VM is not running: \(id)"
    case .stopRejected(let id): return "VM rejected graceful shutdown: \(id)"
    }
  }
}
