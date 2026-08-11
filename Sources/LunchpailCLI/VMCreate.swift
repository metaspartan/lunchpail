import ArgumentParser
import Foundation
import LunchpailCore

struct VMCreate: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "create",
    abstract: "Create and install a new virtual machine.",
    subcommands: [VMMacOSCreate.self]
  )
}

struct VMMacOSCreate: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "macos",
    abstract: "Install a new Apple silicon macOS VM from a local IPSW."
  )

  @Argument(help: "VM name.")
  var name: String

  @Option(help: "Path to a local macOS restore image (.ipsw).")
  var ipsw: String

  @Option(help: "Destination directory. Defaults to Lunchpail's managed VM directory.")
  var destination: String?

  @Option(help: "Virtual CPU count.")
  var cpuCount = min(ProcessInfo.processInfo.processorCount, 8)

  @Option(name: .customLong("memory-gib"), help: "Memory size in GiB.")
  var memoryGiB = 8

  @Option(name: .customLong("disk-gib"), help: "Sparse disk capacity in GiB.")
  var diskGiB = 80

  @Option(help: "Metal profile metadata recorded in the manifest.")
  var profile = "stock"

  @Flag(help: "Emit machine-readable JSON after installation.")
  var json = false

  mutating func run() async throws {
    let report = try HostInspector().inspect()
    guard report.virtualizationSupported else {
      throw ValidationError("Virtualization.framework is unavailable on this host")
    }
    guard report.virtualizationEntitlementPresent else {
      throw ValidationError(
        "the current executable lacks com.apple.security.virtualization; run `make sign`"
      )
    }
    guard memoryGiB > 0, diskGiB > 0 else {
      throw ValidationError("memory and disk sizes must be positive")
    }
    let gibibyte = UInt64(1_024 * 1_024 * 1_024)
    let memory = UInt64(memoryGiB).multipliedReportingOverflow(by: gibibyte)
    let disk = UInt64(diskGiB).multipliedReportingOverflow(by: gibibyte)
    guard !memory.overflow, !disk.overflow else {
      throw ValidationError("memory or disk size is too large")
    }

    let registry = VMRegistry()
    let destinationURL =
      destination.map {
        URL(
          fileURLWithPath: NSString(string: $0).expandingTildeInPath,
          isDirectory: true
        ).standardizedFileURL
      } ?? registry.vmDirectoryURL.appendingPathComponent(name, isDirectory: true)
    let restoreImageURL = URL(
      fileURLWithPath: NSString(string: ipsw).expandingTildeInPath
    ).standardizedFileURL
    let printer = InstallProgressPrinter()
    let emitProgress = !json
    let installed = try await MacVMInstaller().install(
      MacVMInstallRequest(
        name: name,
        destinationDirectoryURL: destinationURL,
        restoreImageURL: restoreImageURL,
        cpuCount: cpuCount,
        memoryBytes: memory.partialValue,
        diskBytes: disk.partialValue,
        metalProfileID: profile
      )
    ) { fraction in
      if emitProgress { printer.update(fraction) }
    }
    _ = try registry.register(
      manifestURL: URL(fileURLWithPath: installed.manifestPath)
    )
    if json {
      try Output.json(installed)
    } else {
      print("installed \(installed.name)")
      print("manifest: \(installed.manifestPath)")
      print("macOS: \(installed.operatingSystemVersion) (\(installed.buildVersion))")
      print(String(format: "elapsed: %.1f seconds", installed.elapsedSeconds))
    }
  }
}

private final class InstallProgressPrinter: @unchecked Sendable {
  private let lock = NSLock()
  private var lastPercent = -1

  func update(_ fraction: Double) {
    lock.withLock {
      let percent = min(100, max(0, Int(fraction * 100)))
      guard percent == 100 || percent >= lastPercent + 5 else { return }
      lastPercent = percent
      Output.error("installing macOS: \(percent)%")
    }
  }
}
