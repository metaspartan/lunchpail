import Foundation
import LunchpailCore

struct VMDiscoveryService: Sendable {
  private let registry = VMRegistry()

  func discover() -> [VMRecord] {
    (try? registry.list().map(record(for:))) ?? []
  }

  func remember(_ url: URL) {
    _ = try? registry.register(manifestURL: url)
  }

  private func record(for entry: VMInventoryEntry) -> VMRecord {
    VMRecord(
      manifestURL: entry.manifestURL,
      name: entry.name,
      cpuCount: entry.cpuCount,
      memoryBytes: entry.memoryBytes,
      metalProfileID: entry.metalProfileID,
      validationState: entry.isValid
        ? .ready
        : .invalid(entry.validationError ?? "Invalid manifest")
    )
  }
}
