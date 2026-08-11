import ArgumentParser
import Foundation
import LunchpailCore

struct VMValidate: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: "Validate a manifest, its files, and the resulting Virtualization configuration."
  )

  @Argument(help: "VM ID, unique name, manifest path, or VM directory.")
  var vm: String

  mutating func run() async throws {
    let url = try VMRegistry().resolve(vm).manifestURL
    try await MainActor.run {
      _ = try MacVMConfigurationBuilder.build(manifestURL: url)
    }
    print("valid VM manifest: \(url.path)")
  }
}

struct VMRun: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Run a macOS VM in this foreground process.",
    aliases: ["foreground"]
  )

  @Argument(help: "VM ID, unique name, manifest path, or VM directory.")
  var vm: String

  mutating func run() async throws {
    let report = try HostInspector().inspect()
    guard report.virtualizationEntitlementPresent else {
      throw ValidationError(
        "the current executable lacks com.apple.security.virtualization; run `make sign`")
    }
    let url = try VMRegistry().resolve(vm).manifestURL
    try await runVM(manifestURL: url)
  }

  @MainActor
  private func runVM(manifestURL: URL) async throws {
    let manifest = try VMManifest.load(from: manifestURL)
    if manifest.metalProfileID != MetalProfileRegistry.stock.id {
      let preference = try HostMetalPreferenceManager().read()
      guard preference.enabled == true else {
        throw ValidationError(
          "Metal host bridge is disabled for profile \(manifest.metalProfileID); run `lunchpail metal host enable --acknowledge-private-api-risk` first"
        )
      }
    }
    let lifecycleLock = try VMDirectoryLock(
      directoryURL: manifestURL.deletingLastPathComponent(),
      mode: .exclusive
    )
    defer { withExtendedLifetime(lifecycleLock) {} }
    let configuration = try MacVMConfigurationBuilder.build(manifestURL: manifestURL)
    print("starting \(manifest.name) with Metal profile metadata `\(manifest.metalProfileID)`")
    print(
      "note: the VM device is host-backed, but profile injection happens only when a guest workload is launched"
    )
    let runner = MacVMRunner(configuration: configuration)
    print("press Control-C once for a graceful guest shutdown; twice to force stop")
    try await runner.runHandlingTerminationSignals()
    print("VM stopped")
  }
}

struct VMStart: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "start",
    abstract: "Start a VM through the local Lunchpail API service."
  )

  @Argument(help: "VM ID, unique name, manifest path, or VM directory.")
  var vm: String

  @Option(help: "Local API port.")
  var apiPort = 7777

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let entry = try VMRegistry().resolve(vm)
    let status = try await LunchpailCLIAPI.client(port: apiPort).start(vmID: entry.id)
    if json {
      try Output.json(status)
    } else {
      print("\(entry.name): \(status.phase.rawValue)")
    }
  }
}

struct VMStop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: "Stop a VM owned by the local Lunchpail API service."
  )

  @Argument(help: "VM ID, unique name, manifest path, or VM directory.")
  var vm: String

  @Option(help: "Local API port.")
  var apiPort = 7777

  @Flag(help: "Force stop without guest shutdown.")
  var force = false

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let entry = try VMRegistry().resolve(vm)
    let status = try await LunchpailCLIAPI.client(port: apiPort).stop(
      vmID: entry.id,
      force: force
    )
    if json {
      try Output.json(status)
    } else {
      print("\(entry.name): \(status.phase.rawValue)")
    }
  }
}

struct VMStatus: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Read a VM runtime state from the local Lunchpail API service."
  )

  @Argument(help: "VM ID, unique name, manifest path, or VM directory.")
  var vm: String

  @Option(help: "Local API port.")
  var apiPort = 7777

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let entry = try VMRegistry().resolve(vm)
    let value = try await LunchpailCLIAPI.client(port: apiPort).vm(vmID: entry.id)
    if json {
      try Output.json(value)
    } else {
      print("\(value.vm.name): \(value.runtime.phase.rawValue)")
      if let error = value.runtime.error { print("error: \(error)") }
    }
  }
}
