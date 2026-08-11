import Foundation

public enum MetalProfileMaturity: String, Codable, Sendable {
  case stock
  case research
  case certified
}

public struct MetalProfile: Codable, Equatable, Sendable {
  public let id: String
  public let summary: String
  public let maturity: MetalProfileMaturity
  public let appleFamilyMaximum: Int?
  public let maxThreadgroupMemoryBytes: Int?
  public let recommendedWorkingSetBytes: UInt64?
  public let validatedHostChips: [String]
  public let validatedHostVersions: [String]
  public let validatedGuestVersions: [String]
  public let validatedWorkloads: [String]
  public let evidenceURL: URL?

  public var requiresShim: Bool { appleFamilyMaximum != nil }

  public func environment(shimURL: URL) throws -> [String: String] {
    guard requiresShim, let family = appleFamilyMaximum else { return [:] }
    guard (1001...1010).contains(family) else {
      throw MetalProfileError.invalidAppleFamily(family)
    }

    var result = [
      "DYLD_INSERT_LIBRARIES": shimURL.path,
      "LUNCHPAIL_METAL_APPLE_FAMILY_MAX": String(family),
    ]
    if let memory = maxThreadgroupMemoryBytes {
      guard (16_384...1_048_576).contains(memory) else {
        throw MetalProfileError.invalidThreadgroupMemory(memory)
      }
      result["LUNCHPAIL_METAL_MAX_THREADGROUP_MEMORY"] = String(memory)
    }
    if let workingSet = recommendedWorkingSetBytes {
      result["LUNCHPAIL_METAL_RECOMMENDED_WORKING_SET_SIZE"] = String(workingSet)
    }
    return result
  }

  public func warnings(for host: HostReport) -> [String] {
    guard maturity != .stock else { return [] }
    var warnings: [String] = []
    if !validatedHostChips.contains(where: { host.chip.localizedCaseInsensitiveContains($0) }) {
      warnings.append("profile has no evidence for host chip \(host.chip)")
    }
    if !validatedHostVersions.contains(where: { host.osVersion.contains($0) }) {
      warnings.append("profile has no guest benchmark evidence for host \(host.osVersion)")
    }
    if !host.unrestrictedGraphicsPreference.isSet
      || host.unrestrictedGraphicsPreference.enabled != true
    {
      warnings.append("unrestricted paravirtualized-graphics host preference is not enabled")
    }
    return warnings
  }
}

public enum MetalProfileError: LocalizedError, Equatable {
  case unknownProfile(String)
  case invalidAppleFamily(Int)
  case invalidThreadgroupMemory(Int)

  public var errorDescription: String? {
    switch self {
    case .unknownProfile(let id):
      return "unknown Metal profile: \(id)"
    case .invalidAppleFamily(let family):
      return "invalid Apple GPU family value: \(family)"
    case .invalidThreadgroupMemory(let bytes):
      return "invalid maximum threadgroup memory: \(bytes) bytes"
    }
  }
}

public enum MetalProfileRegistry {
  public static let stock = MetalProfile(
    id: "stock",
    summary: "Apple's unmodified virtual-GPU capability answers",
    maturity: .stock,
    appleFamilyMaximum: nil,
    maxThreadgroupMemoryBytes: nil,
    recommendedWorkingSetBytes: nil,
    validatedHostChips: [],
    validatedHostVersions: [],
    validatedGuestVersions: [],
    validatedWorkloads: [],
    evidenceURL: nil
  )

  public static let cuaM1LlamaCPP = MetalProfile(
    id: "cua-m1-llamacpp",
    summary: "Cua's Apple-family 9 / 64 KiB research profile for llama.cpp on M1 Ultra",
    maturity: .research,
    appleFamilyMaximum: 1009,
    maxThreadgroupMemoryBytes: 65_536,
    recommendedWorkingSetBytes: nil,
    validatedHostChips: ["M1 Ultra"],
    validatedHostVersions: ["26.6.1", "Version 27.0"],
    validatedGuestVersions: ["26.5.2"],
    validatedWorkloads: ["llama.cpp b10167", "llama.cpp b10359", "MLX-LM 0.31.3 compatibility"],
    evidenceURL: URL(
      string: "https://github.com/trycua/cua/blob/main/blog/gpu-passthrough-macos-vms.md")
  )

  public static let all = [stock, cuaM1LlamaCPP]

  public static func profile(id: String) throws -> MetalProfile {
    guard let profile = all.first(where: { $0.id == id }) else {
      throw MetalProfileError.unknownProfile(id)
    }
    return profile
  }
}
