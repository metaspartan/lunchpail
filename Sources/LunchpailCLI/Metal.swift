import ArgumentParser
import Foundation
import LunchpailCore

struct Metal: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect and run process-scoped Metal capability containers.",
    subcommands: [
      MetalProfiles.self,
      MetalProbe.self,
      MetalEnvironment.self,
      MetalRun.self,
      MetalBenchmark.self,
      MetalHost.self,
    ]
  )
}

struct MetalRun: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Verify a Metal profile, then replace Lunchpail with one profiled workload process.",
    discussion:
      "The capability canary runs first. Physical-host execution is refused by default because this profile is intended for Apple's paravirtualized guest device.",
    aliases: ["exec", "container"]
  )

  @Option(help: "Profile identifier. Use stock to launch without injection.")
  var profile = "cua-m1-llamacpp"

  @Option(help: "Path to lunchpail-metal-probe. Defaults to the CLI's directory.")
  var probePath: String?

  @Option(help: "Path to libLunchpailMetalShim.dylib. Defaults to the CLI's directory.")
  var shimPath: String?

  @Flag(help: "Allow a research profile to run on a physical Metal device (testing only).")
  var allowPhysicalHost = false

  @Argument(
    parsing: .captureForPassthrough,
    help: "Workload executable and arguments. Place these after --."
  )
  var workload: [String]

  mutating func run() throws {
    var command = workload.first == "--" ? Array(workload.dropFirst()) : workload
    guard !command.isEmpty else {
      throw ValidationError("provide a workload after --")
    }
    let selected = try MetalProfileRegistry.profile(id: profile)
    guard selected.requiresShim else {
      try ProcessReplacement.run(command, additionalEnvironment: [:])
    }

    let artifacts = try MetalArtifactPaths.resolve(
      probePath: probePath,
      shimPath: shimPath
    )
    let comparison = try MetalProbeRunner().compare(
      profile: selected,
      artifacts: artifacts
    )
    guard
      allowPhysicalHost
        || comparison.stock.device.localizedCaseInsensitiveContains("paravirtual")
    else {
      throw ValidationError(
        "refusing research profile on physical device `\(comparison.stock.device)`; run this command inside the macOS guest"
      )
    }
    guard comparison.changedOnlyExpectedCapabilities else {
      throw ValidationError("Metal canary changed capabilities outside the selected profile")
    }

    let targetURL = try ProcessReplacement.resolveExecutable(command[0])
    let targetArchitectures = try architectures(of: targetURL)
    let shimArchitectures = try architectures(of: artifacts.shimURL)
    guard !targetArchitectures.isDisjoint(with: shimArchitectures) else {
      throw ValidationError(
        "cannot inject \(shimArchitectures.sorted().joined(separator: ",")) shim into \(targetArchitectures.sorted().joined(separator: ",")) workload `\(targetURL.path)`"
      )
    }
    command[0] = targetURL.path

    Output.error(
      "Lunchpail verified \(profile) on \(comparison.stock.device); launching \(command[0])"
    )
    let environment = try selected.environment(shimURL: artifacts.shimURL)
    try ProcessReplacement.run(command, additionalEnvironment: environment)
  }

  private func architectures(of url: URL) throws -> Set<String> {
    let result = try CommandRunner().checkedRun(
      executable: URL(fileURLWithPath: "/usr/bin/lipo"),
      arguments: ["-archs", url.path]
    )
    let values = result.stdout.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !values.isEmpty else {
      throw ValidationError("could not determine Mach-O architecture for \(url.path)")
    }
    return Set(values)
  }

}

struct MetalProfiles: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "profiles",
    aliases: ["list", "ls"]
  )

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    if json {
      try Output.json(MetalProfileRegistry.all)
      return
    }
    for profile in MetalProfileRegistry.all {
      print("\(profile.id) [\(profile.maturity.rawValue)]")
      print("  \(profile.summary)")
      if let evidence = profile.evidenceURL {
        print("  evidence: \(evidence.absoluteString)")
      }
    }
  }
}

struct MetalProbe: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe",
    abstract: "Compare stock and profiled Metal capability answers in local probe processes."
  )

  @Option(help: "Profile identifier.")
  var profile = "cua-m1-llamacpp"

  @Option(help: "Path to lunchpail-metal-probe. Defaults to the CLI's build directory.")
  var probePath: String?

  @Option(help: "Path to libLunchpailMetalShim.dylib. Defaults to the CLI's build directory.")
  var shimPath: String?

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    let selected = try MetalProfileRegistry.profile(id: profile)
    let artifacts = try MetalArtifactPaths.resolve(
      probePath: probePath,
      shimPath: shimPath
    )

    let comparison = try MetalProbeRunner().compare(profile: selected, artifacts: artifacts)
    if json {
      try Output.json(comparison)
      return
    }

    print("Metal capability probe: \(comparison.profileID)")
    print("  device: \(comparison.stock.device)")
    print(
      "  Apple family \(comparison.stock.family): \(comparison.stock.supportsFamily) -> \(comparison.profiled.supportsFamily)"
    )
    print(
      "  threadgroup memory: \(comparison.stock.maxThreadgroupMemoryBytes) -> \(comparison.profiled.maxThreadgroupMemoryBytes) bytes"
    )
    print("  expected-only change: \(comparison.changedOnlyExpectedCapabilities ? "yes" : "no")")
    print("\nThis verifies interception in two host processes; it does not certify a VM workload.")
  }
}

struct MetalEnvironment: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "env",
    abstract: "Print the environment for launching one guest process with a profile."
  )

  @Option(help: "Profile identifier.")
  var profile = "cua-m1-llamacpp"

  @Option(help: "Guest path to libLunchpailMetalShim.dylib.")
  var shim: String

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    let selected = try MetalProfileRegistry.profile(id: profile)
    let environment = try selected.environment(shimURL: URL(fileURLWithPath: shim))
    if json {
      try Output.json(environment)
      return
    }
    let assignments = environment.sorted(by: { $0.key < $1.key }).map {
      "\($0.key)=\(Output.shellQuote($0.value))"
    }
    print("env " + assignments.joined(separator: " ") + " -- <workload> [arguments...]")
  }
}

struct MetalHost: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "host",
    abstract: "Manage the private per-user host graphics preference transactionally.",
    subcommands: [MetalHostStatus.self, MetalHostEnable.self, MetalHostRestore.self]
  )
}

struct MetalHostStatus: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "status")

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    let manager = HostMetalPreferenceManager()
    let preference = try manager.read()
    if json {
      try Output.json(preference)
      return
    }
    print("unrestricted preference: \(preference.description)")
    print("restore journal: \(manager.hasPendingBackup ? manager.backupURL.path : "none")")
  }
}

struct MetalHostEnable: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: "Journal the current value, then enable the private host preference."
  )

  @Flag(help: "Required acknowledgement that this is an undocumented, per-user setting.")
  var acknowledgePrivateAPIRisk = false

  mutating func run() throws {
    guard acknowledgePrivateAPIRisk else {
      throw ValidationError(
        "refusing to change the host setting without --acknowledge-private-api-risk; stop all macOS VMs first"
      )
    }
    let manager = HostMetalPreferenceManager()
    let previous = try manager.enable()
    print("enabled unrestricted paravirtualized graphics")
    print("previous value: \(previous.description)")
    print("restore journal: \(manager.backupURL.path)")
  }
}

struct MetalHostRestore: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "restore",
    abstract: "Restore the host preference from Lunchpail's journal."
  )

  mutating func run() throws {
    let manager = HostMetalPreferenceManager()
    let restored = try manager.restore()
    print("restored unrestricted preference to: \(restored.description)")
  }
}
