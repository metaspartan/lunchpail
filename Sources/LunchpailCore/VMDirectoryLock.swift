import Darwin
import Foundation

public final class VMDirectoryLock: @unchecked Sendable {
  public enum Mode: Sendable {
    case shared
    case exclusive
  }

  private var handles: [FileHandle] = []

  public init(directoryURL: URL, mode: Mode) throws {
    let fileManager = FileManager.default
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    let lunchpailLock = directoryURL.appendingPathComponent(".lunchpail.lock")
    if !fileManager.fileExists(atPath: lunchpailLock.path) {
      guard
        fileManager.createFile(
          atPath: lunchpailLock.path,
          contents: nil,
          attributes: [.posixPermissions: 0o600]
        )
      else {
        throw VMDirectoryLockError.cannotCreate(lunchpailLock.path)
      }
    }
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lunchpailLock.path)

    var lockURLs = [lunchpailLock]
    let lumeConfig = directoryURL.appendingPathComponent("config.json")
    if fileManager.fileExists(atPath: lumeConfig.path) {
      lockURLs.append(lumeConfig)
    }

    do {
      for url in lockURLs.sorted(by: { $0.path < $1.path }) {
        let handle = try FileHandle(forUpdating: url)
        let operation = mode == .exclusive ? (LOCK_EX | LOCK_NB) : (LOCK_SH | LOCK_NB)
        guard flock(handle.fileDescriptor, operation) == 0 else {
          try? handle.close()
          throw VMDirectoryLockError.busy(directoryURL.path)
        }
        handles.append(handle)
      }
    } catch {
      unlock()
      throw error
    }
  }

  deinit {
    unlock()
  }

  private func unlock() {
    for handle in handles.reversed() {
      flock(handle.fileDescriptor, LOCK_UN)
      try? handle.close()
    }
    handles.removeAll()
  }
}

public enum VMDirectoryLockError: LocalizedError, Equatable {
  case cannotCreate(String)
  case busy(String)

  public var errorDescription: String? {
    switch self {
    case .cannotCreate(let path): return "cannot create VM lifecycle lock: \(path)"
    case .busy(let path): return "virtual machine is busy or already running: \(path)"
    }
  }
}
