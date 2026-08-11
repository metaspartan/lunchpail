import Darwin
import Foundation
import Security

public struct APITokenRecord: Sendable, Equatable {
  public let value: String
  public let url: URL
  public let wasCreated: Bool
}

public struct APITokenStore: Sendable {
  public let tokenURL: URL

  public init(tokenURL: URL? = nil) {
    self.tokenURL =
      tokenURL
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".lunchpail/state/api-token")
  }

  public func loadOrCreate() throws -> APITokenRecord {
    let directory = tokenURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

    let lockURL = tokenURL.appendingPathExtension("lock")
    let descriptor = lockURL.path.withCString {
      Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
      throw APITokenError.cannotLock(lockURL.path)
    }
    defer { Darwin.close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else {
      throw APITokenError.cannotLock(lockURL.path)
    }
    defer { flock(descriptor, LOCK_UN) }

    if FileManager.default.fileExists(atPath: tokenURL.path) {
      var status = stat()
      guard lstat(tokenURL.path, &status) == 0,
        status.st_mode & S_IFMT == S_IFREG,
        status.st_uid == getuid()
      else {
        throw APITokenError.unsafeTokenFile(tokenURL.path)
      }
      let value = try String(contentsOf: tokenURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard value.utf8.count >= 32 else { throw APITokenError.invalidTokenFile(tokenURL.path) }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: tokenURL.path
      )
      return APITokenRecord(value: value, url: tokenURL, wasCreated: false)
    }

    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw APITokenError.generationFailed
    }
    let value = bytes.map { String(format: "%02x", $0) }.joined()
    try Data((value + "\n").utf8).write(to: tokenURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: tokenURL.path
    )
    return APITokenRecord(value: value, url: tokenURL, wasCreated: true)
  }
}

public enum APITokenError: LocalizedError, Equatable {
  case invalidTokenFile(String)
  case unsafeTokenFile(String)
  case cannotLock(String)
  case generationFailed

  public var errorDescription: String? {
    switch self {
    case .invalidTokenFile(let path): return "API token file is invalid: \(path)"
    case .unsafeTokenFile(let path): return "API token is not a user-owned regular file: \(path)"
    case .cannotLock(let path): return "could not lock API token storage: \(path)"
    case .generationFailed: return "could not generate a secure API token"
    }
  }
}
