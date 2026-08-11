import Darwin
import Dispatch
import Foundation
import Virtualization

@MainActor
public final class MacVMRunner {
  private let virtualMachine: VZVirtualMachine
  private let delegate: StopDelegate

  public var displayVirtualMachine: VZVirtualMachine { virtualMachine }

  public init(configuration: VZVirtualMachineConfiguration) {
    self.virtualMachine = VZVirtualMachine(configuration: configuration)
    self.delegate = StopDelegate()
    self.virtualMachine.delegate = delegate
  }

  public func run() async throws {
    try await start()
    try await waitForStop()
  }

  public func start() async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      virtualMachine.start { result in
        continuation.resume(with: result)
      }
    }
  }

  public func waitForStop() async throws {
    try await delegate.waitForStop()
  }

  public func runHandlingTerminationSignals() async throws {
    var signalCount = 0
    let handledSignals = [SIGINT, SIGTERM]
    let sources = handledSignals.map { signalNumber in
      Darwin.signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
      source.setEventHandler { [weak self] in
        Task { @MainActor [weak self] in
          guard let self else { return }
          signalCount += 1
          if signalCount == 1 {
            Self.writeSignalMessage("requesting graceful guest shutdown")
            _ = try? self.requestStop()
          } else {
            Self.writeSignalMessage("forcing virtual machine stop")
            try? await self.forceStop()
          }
        }
      }
      source.resume()
      return source
    }
    defer {
      for source in sources {
        source.cancel()
      }
      for signal in handledSignals {
        Darwin.signal(signal, SIG_DFL)
      }
    }
    try await run()
  }

  @discardableResult
  public func requestStop() throws -> Bool {
    try virtualMachine.requestStop()
    return true
  }

  public func forceStop() async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      virtualMachine.stop { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
    delegate.forcedStopDidComplete()
  }

  private static func writeSignalMessage(_ message: String) {
    FileHandle.standardError.write(Data(("Lunchpail: \(message)\n").utf8))
  }
}

@MainActor
private final class StopDelegate: NSObject, @preconcurrency VZVirtualMachineDelegate {
  private var continuation: CheckedContinuation<Void, Error>?
  private var terminalResult: Result<Void, Error>?

  func waitForStop() async throws {
    if let terminalResult {
      return try terminalResult.get()
    }
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      self.continuation = continuation
    }
  }

  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    finish(.success(()))
  }

  func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: any Error) {
    finish(.failure(error))
  }

  func forcedStopDidComplete() {
    finish(.success(()))
  }

  private func finish(_ result: Result<Void, Error>) {
    terminalResult = result
    continuation?.resume(with: result)
    continuation = nil
  }
}
