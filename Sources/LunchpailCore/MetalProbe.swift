import Foundation

public struct MetalProbeResult: Codable, Equatable, Sendable {
  public let device: String
  public let family: Int
  public let supportsFamily: Bool
  public let maxThreadgroupMemoryBytes: Int
  public let recommendedWorkingSetBytes: UInt64
  public let supportsMetal3: Bool

  public init(output: String) throws {
    let values = Dictionary(
      uniqueKeysWithValues: output.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
      })
    guard
      let device = values["device"],
      let familyRaw = values["family"], let family = Int(familyRaw),
      let supportsRaw = values["supports_family"],
      let supportsFamily = Bool(strictText: supportsRaw),
      let memoryRaw = values["max_threadgroup_memory"], let memory = Int(memoryRaw),
      let workingSetRaw = values["recommended_working_set"],
      let workingSet = UInt64(workingSetRaw),
      let metal3Raw = values["supports_metal3"],
      let supportsMetal3 = Bool(strictText: metal3Raw)
    else {
      throw MetalProbeError.malformedOutput(output)
    }
    self.device = device
    self.family = family
    self.supportsFamily = supportsFamily
    self.maxThreadgroupMemoryBytes = memory
    self.recommendedWorkingSetBytes = workingSet
    self.supportsMetal3 = supportsMetal3
  }
}

public struct MetalProbeComparison: Codable, Equatable, Sendable {
  public let profileID: String
  public let stock: MetalProbeResult
  public let profiled: MetalProbeResult

  public var changedOnlyExpectedCapabilities: Bool {
    stock.device == profiled.device
      && stock.family == profiled.family
      && (!stock.supportsFamily || profiled.supportsFamily)
      && profiled.maxThreadgroupMemoryBytes >= stock.maxThreadgroupMemoryBytes
      && stock.recommendedWorkingSetBytes == profiled.recommendedWorkingSetBytes
      && stock.supportsMetal3 == profiled.supportsMetal3
  }
}

public enum MetalProbeError: LocalizedError {
  case missingArtifact(String)
  case incompleteArtifactPaths
  case malformedOutput(String)
  case profileDidNotTakeEffect(String)

  public var errorDescription: String? {
    switch self {
    case .missingArtifact(let path):
      return "required Metal artifacts were not found in: \(path)"
    case .incompleteArtifactPaths:
      return "provide both Metal probe and shim paths, or neither"
    case .malformedOutput(let output):
      return "Metal probe returned malformed output: \(output)"
    case .profileDidNotTakeEffect(let id):
      return "Metal profile \(id) did not produce its configured capability answers"
    }
  }
}

public struct MetalArtifactPaths: Sendable {
  public let probeURL: URL
  public let shimURL: URL

  public init(probeURL: URL, shimURL: URL) {
    self.probeURL = probeURL
    self.shimURL = shimURL
  }

  public static func resolve(
    probePath: String?,
    shimPath: String?,
    executablePath: String = CommandLine.arguments[0]
  ) throws -> Self {
    if let probePath, let shimPath {
      return Self(
        probeURL: URL(fileURLWithPath: probePath),
        shimURL: URL(fileURLWithPath: shimPath)
      )
    }
    guard probePath == nil, shimPath == nil else {
      throw MetalProbeError.incompleteArtifactPaths
    }
    return try adjacentToExecutable(executablePath)
  }

  public static func adjacentToExecutable(_ executablePath: String = CommandLine.arguments[0])
    throws -> Self
  {
    try findAdjacentToExecutable(executablePath, environmentOverride: true)
  }

  public static func installedAdjacentToExecutable(
    _ executablePath: String = CommandLine.arguments[0]
  ) throws -> Self {
    try findAdjacentToExecutable(executablePath, environmentOverride: false)
  }

  private static func findAdjacentToExecutable(
    _ executablePath: String,
    environmentOverride: Bool
  ) throws -> Self {
    let executableURL = URL(fileURLWithPath: executablePath)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let executableDirectory = executableURL.deletingLastPathComponent()
    var directories: [URL] = []
    if environmentOverride,
      let override = ProcessInfo.processInfo.environment["LUNCHPAIL_ARTIFACT_DIR"]
    {
      directories.append(URL(fileURLWithPath: override, isDirectory: true))
    }
    directories.append(executableDirectory)
    directories.append(
      executableDirectory.deletingLastPathComponent()
        .appendingPathComponent("libexec/lunchpail", isDirectory: true)
    )
    if let resourceURL = Bundle.main.resourceURL {
      directories.append(resourceURL)
    }
    for directory in directories {
      let probe = directory.appendingPathComponent("lunchpail-metal-probe")
      let shim = directory.appendingPathComponent("libLunchpailMetalShim.dylib")
      if FileManager.default.isExecutableFile(atPath: probe.path),
        FileManager.default.fileExists(atPath: shim.path)
      {
        return Self(probeURL: probe, shimURL: shim)
      }
    }
    throw MetalProbeError.missingArtifact(
      directories.map(\.path).joined(separator: ", ")
    )
  }
}

public struct MetalProbeRunner: Sendable {
  private let runner: any CommandRunning

  public init(runner: any CommandRunning = CommandRunner()) {
    self.runner = runner
  }

  public func compare(
    profile: MetalProfile,
    artifacts: MetalArtifactPaths
  ) throws -> MetalProbeComparison {
    guard profile.requiresShim, let family = profile.appleFamilyMaximum else {
      throw MetalProbeError.profileDidNotTakeEffect(profile.id)
    }
    let arguments = [String(family)]
    let stockResult = try checkedProbe(
      executable: artifacts.probeURL,
      arguments: arguments,
      environment: nil
    )
    let environment = try profile.environment(shimURL: artifacts.shimURL)
    let profiledResult = try checkedProbe(
      executable: artifacts.probeURL,
      arguments: arguments,
      environment: environment
    )
    let comparison = MetalProbeComparison(
      profileID: profile.id,
      stock: stockResult,
      profiled: profiledResult
    )
    guard profiledResult.supportsFamily,
      profiledResult.maxThreadgroupMemoryBytes
        == max(
          profile.maxThreadgroupMemoryBytes ?? stockResult.maxThreadgroupMemoryBytes,
          stockResult.maxThreadgroupMemoryBytes
        ),
      profiledResult.recommendedWorkingSetBytes
        == max(
          profile.recommendedWorkingSetBytes ?? stockResult.recommendedWorkingSetBytes,
          stockResult.recommendedWorkingSetBytes
        ),
      comparison.changedOnlyExpectedCapabilities
    else {
      throw MetalProbeError.profileDidNotTakeEffect(profile.id)
    }
    return comparison
  }

  private func checkedProbe(
    executable: URL,
    arguments: [String],
    environment: [String: String]?
  ) throws -> MetalProbeResult {
    let result = try runner.run(
      executable: executable,
      arguments: arguments,
      environment: environment
    )
    guard result.status == 0 else {
      throw CommandFailure(
        executable: executable.path,
        arguments: arguments,
        result: result
      )
    }
    return try MetalProbeResult(output: result.stdout)
  }
}

extension Bool {
  fileprivate init?(strictText: String) {
    switch strictText.lowercased() {
    case "true": self = true
    case "false": self = false
    default: return nil
    }
  }
}
