import CryptoKit
import Foundation

public struct LlamaBenchmarkMeasurement: Codable, Equatable, Sendable {
  public let tokenCount: Int
  public let averageTokensPerSecond: Double
  public let standardDeviationTokensPerSecond: Double
  public let samplesTokensPerSecond: [Double]
}

public struct LlamaBenchmarkSummary: Codable, Equatable, Sendable {
  public let buildCommit: String
  public let buildNumber: Int
  public let cpuInfo: String
  public let gpuInfo: String
  public let backends: String
  public let modelFilename: String
  public let modelType: String
  public let prompt: LlamaBenchmarkMeasurement
  public let generation: LlamaBenchmarkMeasurement

  public init(jsonData: Data) throws {
    let entries: [RawLlamaBenchmarkEntry]
    do {
      entries = try JSONDecoder().decode([RawLlamaBenchmarkEntry].self, from: jsonData)
    } catch {
      throw LlamaBenchmarkError.malformedJSON(error.localizedDescription)
    }
    guard let promptEntry = entries.first(where: { $0.nPrompt > 0 && $0.nGen == 0 }) else {
      throw LlamaBenchmarkError.missingPromptMeasurement
    }
    guard let generationEntry = entries.first(where: { $0.nPrompt == 0 && $0.nGen > 0 }) else {
      throw LlamaBenchmarkError.missingGenerationMeasurement
    }
    guard promptEntry.buildCommit == generationEntry.buildCommit,
      promptEntry.buildNumber == generationEntry.buildNumber,
      promptEntry.modelFilename == generationEntry.modelFilename,
      promptEntry.samplesTokensPerSecond.allSatisfy({ $0 > 0 && $0.isFinite }),
      generationEntry.samplesTokensPerSecond.allSatisfy({ $0 > 0 && $0.isFinite }),
      promptEntry.averageTokensPerSecond > 0,
      generationEntry.averageTokensPerSecond > 0
    else {
      throw LlamaBenchmarkError.inconsistentMeasurements
    }

    buildCommit = promptEntry.buildCommit
    buildNumber = promptEntry.buildNumber
    cpuInfo = promptEntry.cpuInfo
    gpuInfo = promptEntry.gpuInfo
    backends = promptEntry.backends
    modelFilename = promptEntry.modelFilename
    modelType = promptEntry.modelType
    prompt = LlamaBenchmarkMeasurement(
      tokenCount: promptEntry.nPrompt,
      averageTokensPerSecond: promptEntry.averageTokensPerSecond,
      standardDeviationTokensPerSecond: promptEntry.standardDeviationTokensPerSecond,
      samplesTokensPerSecond: promptEntry.samplesTokensPerSecond
    )
    generation = LlamaBenchmarkMeasurement(
      tokenCount: generationEntry.nGen,
      averageTokensPerSecond: generationEntry.averageTokensPerSecond,
      standardDeviationTokensPerSecond: generationEntry.standardDeviationTokensPerSecond,
      samplesTokensPerSecond: generationEntry.samplesTokensPerSecond
    )
  }
}

public enum LlamaBenchmarkError: LocalizedError, Equatable {
  case malformedJSON(String)
  case missingPromptMeasurement
  case missingGenerationMeasurement
  case inconsistentMeasurements

  public var errorDescription: String? {
    switch self {
    case .malformedJSON(let detail): return "malformed llama-bench JSON: \(detail)"
    case .missingPromptMeasurement: return "llama-bench JSON has no prompt measurement"
    case .missingGenerationMeasurement: return "llama-bench JSON has no generation measurement"
    case .inconsistentMeasurements: return "llama-bench measurements are inconsistent or invalid"
    }
  }
}

public struct ArtifactDigest: Codable, Equatable, Sendable {
  public let role: String
  public let path: String
  public let byteCount: UInt64
  public let sha256: String

  public init(role: String, url: URL) throws {
    self.role = role
    path = url.standardizedFileURL.path
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    byteCount = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 4 * 1_024 * 1_024), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

public struct CertificationSystem: Codable, Equatable, Sendable {
  public let chip: String
  public let architecture: String
  public let productVersion: String
  public let buildVersion: String

  public init(
    chip: String,
    architecture: String,
    productVersion: String,
    buildVersion: String
  ) {
    self.chip = chip
    self.architecture = architecture
    self.productVersion = productVersion
    self.buildVersion = buildVersion
  }
}

public struct MetalLlamaCertification: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let recordedAt: String
  public let system: CertificationSystem
  public let profileID: String
  public let capabilityProbe: MetalProbeComparison
  public let artifacts: [ArtifactDigest]
  public let arguments: [String]
  public let stock: LlamaBenchmarkSummary
  public let profiled: LlamaBenchmarkSummary
  public let promptSpeedup: Double
  public let generationSpeedup: Double
  public let minimumPromptSpeedup: Double
  public let minimumGenerationSpeedup: Double
  public let validationFailures: [String]
  public let passed: Bool

  public init(
    recordedAt: String,
    system: CertificationSystem,
    profileID: String,
    capabilityProbe: MetalProbeComparison,
    artifacts: [ArtifactDigest],
    arguments: [String],
    stock: LlamaBenchmarkSummary,
    profiled: LlamaBenchmarkSummary,
    minimumPromptSpeedup: Double,
    minimumGenerationSpeedup: Double
  ) {
    schemaVersion = 1
    self.recordedAt = recordedAt
    self.system = system
    self.profileID = profileID
    self.capabilityProbe = capabilityProbe
    self.artifacts = artifacts
    self.arguments = arguments
    self.stock = stock
    self.profiled = profiled
    promptSpeedup =
      profiled.prompt.averageTokensPerSecond
      / stock.prompt.averageTokensPerSecond
    generationSpeedup =
      profiled.generation.averageTokensPerSecond
      / stock.generation.averageTokensPerSecond
    self.minimumPromptSpeedup = minimumPromptSpeedup
    self.minimumGenerationSpeedup = minimumGenerationSpeedup

    var failures: [String] = []
    if stock.buildCommit != profiled.buildCommit || stock.buildNumber != profiled.buildNumber {
      failures.append("stock and profiled runs used different llama.cpp builds")
    }
    if stock.modelType != profiled.modelType {
      failures.append("stock and profiled runs reported different model types")
    }
    if stock.gpuInfo != profiled.gpuInfo {
      failures.append("stock and profiled runs reported different Metal devices")
    }
    if promptSpeedup < minimumPromptSpeedup {
      failures.append(
        "prompt speedup \(promptSpeedup) is below \(minimumPromptSpeedup)"
      )
    }
    if generationSpeedup < minimumGenerationSpeedup {
      failures.append(
        "generation speedup \(generationSpeedup) is below \(minimumGenerationSpeedup)"
      )
    }
    validationFailures = failures
    passed = failures.isEmpty
  }
}

private struct RawLlamaBenchmarkEntry: Decodable {
  let buildCommit: String
  let buildNumber: Int
  let cpuInfo: String
  let gpuInfo: String
  let backends: String
  let modelFilename: String
  let modelType: String
  let nPrompt: Int
  let nGen: Int
  let averageTokensPerSecond: Double
  let standardDeviationTokensPerSecond: Double
  let samplesTokensPerSecond: [Double]

  enum CodingKeys: String, CodingKey {
    case buildCommit = "build_commit"
    case buildNumber = "build_number"
    case cpuInfo = "cpu_info"
    case gpuInfo = "gpu_info"
    case backends
    case modelFilename = "model_filename"
    case modelType = "model_type"
    case nPrompt = "n_prompt"
    case nGen = "n_gen"
    case averageTokensPerSecond = "avg_ts"
    case standardDeviationTokensPerSecond = "stddev_ts"
    case samplesTokensPerSecond = "samples_ts"
  }
}
