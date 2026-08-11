import Foundation

enum LunchpailFormatters {
  static func bytes(_ value: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .memory
    return formatter.string(fromByteCount: Int64(clamping: value))
  }
}
