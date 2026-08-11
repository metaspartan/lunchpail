import Foundation
import Testing

@testable import LunchpailCore

@Test func parsesLlamaBenchmarkPair() throws {
  let summary = try LlamaBenchmarkSummary(jsonData: Data(fixture.utf8))
  #expect(summary.buildNumber == 10_359)
  #expect(summary.buildCommit == "84f712946")
  #expect(summary.prompt.tokenCount == 512)
  #expect(summary.prompt.averageTokensPerSecond == 5_122.03)
  #expect(summary.generation.tokenCount == 128)
  #expect(summary.generation.averageTokensPerSecond == 167.36)
}

@Test func rejectsIncompleteLlamaBenchmark() throws {
  let decoded = try #require(
    JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [Any]
  )
  let promptOnly = try JSONSerialization.data(withJSONObject: [try #require(decoded.first)])
  #expect(throws: LlamaBenchmarkError.missingGenerationMeasurement) {
    _ = try LlamaBenchmarkSummary(jsonData: promptOnly)
  }
}

@Test func hashesArtifactWithoutLoadingItAsOneDataValue() throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-digest-\(UUID().uuidString)")
  try Data("abc".utf8).write(to: url, options: .atomic)
  defer { try? FileManager.default.removeItem(at: url) }

  let digest = try ArtifactDigest(role: "fixture", url: url)
  #expect(digest.byteCount == 3)
  #expect(digest.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

private let fixture = """
  [
    {
      "build_commit": "84f712946",
      "build_number": 10359,
      "cpu_info": "Accelerate, Apple M1 Ultra (Virtual)",
      "gpu_info": "Apple Paravirtual device",
      "backends": "MTL,BLAS",
      "model_filename": "tinyllama.gguf",
      "model_type": "llama 1B Q4_K - Medium",
      "n_prompt": 512,
      "n_gen": 0,
      "avg_ts": 5122.03,
      "stddev_ts": 17.57,
      "samples_ts": [5103.53, 5138.52, 5124.04]
    },
    {
      "build_commit": "84f712946",
      "build_number": 10359,
      "cpu_info": "Accelerate, Apple M1 Ultra (Virtual)",
      "gpu_info": "Apple Paravirtual device",
      "backends": "MTL,BLAS",
      "model_filename": "tinyllama.gguf",
      "model_type": "llama 1B Q4_K - Medium",
      "n_prompt": 0,
      "n_gen": 128,
      "avg_ts": 167.36,
      "stddev_ts": 18.75,
      "samples_ts": [188.95, 155.19, 157.93]
    }
  ]
  """
