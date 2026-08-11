import Foundation
import Metal
import Security
import Virtualization

public struct MetalDeviceReport: Codable, Equatable, Sendable {
  public let name: String
  public let registryID: UInt64
  public let maxThreadgroupMemoryBytes: Int
  public let recommendedWorkingSetBytes: UInt64
  public let supportedAppleFamilies: [Int]
}

public struct HostReport: Codable, Equatable, Sendable {
  public let architecture: String
  public let chip: String
  public let osVersion: String
  public let osBuild: String
  public let logicalCPUCount: Int
  public let physicalMemoryBytes: UInt64
  public let virtualizationSupported: Bool
  public let virtualizationEntitlementPresent: Bool
  public let maximumVMCPUCount: Int
  public let minimumVMMemoryBytes: UInt64
  public let maximumVMMemoryBytes: UInt64
  public let metal: MetalDeviceReport?
  public let unrestrictedGraphicsPreference: HostMetalPreference
  public let preferenceBackupPending: Bool
}

public struct HostInspector: Sendable {
  private let runner: any CommandRunning
  private let preferenceManager: HostMetalPreferenceManager

  public init(
    runner: any CommandRunning = CommandRunner(),
    preferenceManager: HostMetalPreferenceManager? = nil
  ) {
    self.runner = runner
    self.preferenceManager = preferenceManager ?? HostMetalPreferenceManager(runner: runner)
  }

  public func inspect() throws -> HostReport {
    let chip = try trimmedOutput("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
    let osBuild = try trimmedOutput("/usr/bin/sw_vers", ["-buildVersion"])
    let architecture = try trimmedOutput("/usr/bin/uname", ["-m"])
    let processInfo = ProcessInfo.processInfo

    return HostReport(
      architecture: architecture,
      chip: chip,
      osVersion: processInfo.operatingSystemVersionString,
      osBuild: osBuild,
      logicalCPUCount: processInfo.processorCount,
      physicalMemoryBytes: processInfo.physicalMemory,
      virtualizationSupported: VZVirtualMachine.isSupported,
      virtualizationEntitlementPresent: Self.hasVirtualizationEntitlement(),
      maximumVMCPUCount: VZVirtualMachineConfiguration.maximumAllowedCPUCount,
      minimumVMMemoryBytes: VZVirtualMachineConfiguration.minimumAllowedMemorySize,
      maximumVMMemoryBytes: VZVirtualMachineConfiguration.maximumAllowedMemorySize,
      metal: Self.inspectMetal(),
      unrestrictedGraphicsPreference: try preferenceManager.read(),
      preferenceBackupPending: preferenceManager.hasPendingBackup
    )
  }

  private func trimmedOutput(_ executable: String, _ arguments: [String]) throws -> String {
    let result = try runner.run(
      executable: URL(fileURLWithPath: executable),
      arguments: arguments,
      environment: nil
    )
    guard result.status == 0 else {
      throw CommandFailure(executable: executable, arguments: arguments, result: result)
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func inspectMetal() -> MetalDeviceReport? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let families = (1001...1010).compactMap { rawValue -> Int? in
      guard let family = MTLGPUFamily(rawValue: rawValue) else { return nil }
      return device.supportsFamily(family) ? rawValue : nil
    }
    return MetalDeviceReport(
      name: device.name,
      registryID: device.registryID,
      maxThreadgroupMemoryBytes: device.maxThreadgroupMemoryLength,
      recommendedWorkingSetBytes: device.recommendedMaxWorkingSetSize,
      supportedAppleFamilies: families
    )
  }

  private static func hasVirtualizationEntitlement() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let key = "com.apple.security.virtualization" as CFString
    return SecTaskCopyValueForEntitlement(task, key, nil) as? Bool ?? false
  }
}
