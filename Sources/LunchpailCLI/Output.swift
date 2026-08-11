import Foundation
import LunchpailCore

enum Output {
  static func json<T: Encodable>(_ value: T) throws {
    let data = try JSONEncoder.stable.encode(value)
    print(String(decoding: data, as: UTF8.self))
  }

  static func bytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary)
  }

  static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func error(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}
