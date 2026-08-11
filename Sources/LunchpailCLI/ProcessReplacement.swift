import Darwin
import Foundation

enum ProcessReplacement {
  static func resolveExecutable(_ command: String) throws -> URL {
    if command.contains("/") {
      let url = URL(fileURLWithPath: NSString(string: command).expandingTildeInPath)
        .standardizedFileURL
      guard FileManager.default.isExecutableFile(atPath: url.path) else {
        throw ProcessReplacementError.executableNotFound(command)
      }
      return url
    }

    let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    for directory in path.split(separator: ":") {
      let url = URL(fileURLWithPath: String(directory), isDirectory: true)
        .appendingPathComponent(command)
      if FileManager.default.isExecutableFile(atPath: url.path) {
        return url.standardizedFileURL
      }
    }
    throw ProcessReplacementError.executableNotFound(command)
  }

  static func run(
    _ command: [String],
    additionalEnvironment: [String: String]
  ) throws -> Never {
    guard !command.isEmpty else { throw ProcessReplacementError.emptyCommand }

    let assignments = additionalEnvironment.sorted { $0.key < $1.key }.map {
      "\($0.key)=\($0.value)"
    }
    let arguments = ["/usr/bin/env"] + assignments + command
    var pointers: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
    pointers.append(nil)
    defer {
      for pointer in pointers {
        if let pointer { free(UnsafeMutableRawPointer(pointer)) }
      }
    }

    let result = pointers.withUnsafeMutableBufferPointer { buffer -> Int32 in
      guard let path = buffer[0], let baseAddress = buffer.baseAddress else {
        return -1
      }
      return execv(path, baseAddress)
    }
    let failureErrno = errno
    throw ProcessReplacementError.execFailed(
      command: command[0],
      errno: failureErrno,
      detail: result == -1 ? String(cString: strerror(failureErrno)) : "unknown error"
    )
  }
}

enum ProcessReplacementError: LocalizedError, Equatable {
  case emptyCommand
  case executableNotFound(String)
  case execFailed(command: String, errno: Int32, detail: String)

  var errorDescription: String? {
    switch self {
    case .emptyCommand:
      return "cannot execute an empty command"
    case .executableNotFound(let command):
      return "workload executable was not found: \(command)"
    case .execFailed(let command, let errno, let detail):
      return "failed to execute \(command) (errno \(errno)): \(detail)"
    }
  }
}
