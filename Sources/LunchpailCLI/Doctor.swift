import ArgumentParser
import Foundation
import LunchpailCore

struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect host virtualization and Metal readiness."
  )

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    let report = try HostInspector().inspect()
    if json {
      try Output.json(report)
      return
    }

    print("Host")
    print("  chip: \(report.chip)")
    print("  architecture: \(report.architecture)")
    print("  macOS: \(report.osVersion) (\(report.osBuild))")
    print(
      "  CPU / memory: \(report.logicalCPUCount) logical CPUs / \(Output.bytes(report.physicalMemoryBytes))"
    )
    print("Virtualization")
    print("  framework supported: \(yesNo(report.virtualizationSupported))")
    print("  entitlement present: \(yesNo(report.virtualizationEntitlementPresent))")
    print(
      "  VM limits: \(report.maximumVMCPUCount) CPUs / \(Output.bytes(report.maximumVMMemoryBytes)) RAM"
    )
    if let metal = report.metal {
      print("Metal")
      print("  device: \(metal.name)")
      print(
        "  Apple families: \(metal.supportedAppleFamilies.map(String.init).joined(separator: ", "))"
      )
      print("  threadgroup memory: \(Output.bytes(UInt64(metal.maxThreadgroupMemoryBytes)))")
      print("  recommended working set: \(Output.bytes(metal.recommendedWorkingSetBytes))")
    } else {
      print("Metal\n  device: unavailable")
    }
    print("Paravirtualized graphics")
    print("  unrestricted preference: \(report.unrestrictedGraphicsPreference.description)")
    print("  pending restore journal: \(yesNo(report.preferenceBackupPending))")

    if !report.virtualizationEntitlementPresent {
      print("\nAction: run `make sign` before starting a VM from this debug build.")
    }
    if report.preferenceBackupPending {
      print(
        "Action: a previous host preference is journaled; run `lunchpail metal host restore` when no VM is running."
      )
    }
  }

  private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
