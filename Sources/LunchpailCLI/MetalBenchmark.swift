import ArgumentParser
import Foundation
import LunchpailCore

struct MetalBenchmark: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "benchmark",
    abstract: "Produce reproducible stock-versus-profile Metal evidence.",
    subcommands: [MetalBenchmarkLlama.self]
  )
}

struct MetalBenchmarkLlama: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "llama",
    abstract: "Certify a llama.cpp profile with hashed artifacts and repeated stock/profile runs."
  )

  @Option(help: "Path to llama-bench.")
  var llamaBench: String

  @Option(help: "Path to a GGUF model.")
  var model: String

  @Option(help: "Metal profile identifier.")
  var profile = "cua-m1-llamacpp"

  @Option(help: "Path to lunchpail-metal-probe. Defaults to the CLI's directory.")
  var probePath: String?

  @Option(help: "Path to libLunchpailMetalShim.dylib. Defaults to the CLI's directory.")
  var shimPath: String?

  @Option(help: "Number of llama-bench repetitions per measurement.")
  var repetitions = 3

  @Option(help: "CPU threads supplied to llama-bench.")
  var threads = min(ProcessInfo.processInfo.processorCount, 8)

  @Option(help: "Prompt token count.")
  var promptTokens = 512

  @Option(help: "Generated token count.")
  var generationTokens = 128

  @Option(help: "Minimum passing prompt speedup.")
  var minimumPromptSpeedup = 1.10

  @Option(help: "Minimum passing generation speedup.")
  var minimumGenerationSpeedup = 1.10

  @Option(help: "Write the certification JSON to this path instead of standard output.")
  var output: String?

  @Flag(help: "Allow benchmarking on a physical Metal device (testing only).")
  var allowPhysicalHost = false

  mutating func run() throws {
    guard repetitions > 0, threads > 0, promptTokens > 0, generationTokens > 0 else {
      throw ValidationError("repetitions, threads, and token counts must be positive")
    }
    guard minimumPromptSpeedup > 0, minimumGenerationSpeedup > 0 else {
      throw ValidationError("minimum speedups must be positive")
    }

    let benchURL = URL(fileURLWithPath: llamaBench).standardizedFileURL
    let modelURL = URL(fileURLWithPath: model).standardizedFileURL
    guard FileManager.default.isExecutableFile(atPath: benchURL.path) else {
      throw ValidationError("llama-bench is missing or not executable: \(benchURL.path)")
    }
    guard FileManager.default.fileExists(atPath: modelURL.path) else {
      throw ValidationError("model is missing: \(modelURL.path)")
    }

    let selected = try MetalProfileRegistry.profile(id: profile)
    guard selected.requiresShim else {
      throw ValidationError("benchmark certification requires a non-stock profile")
    }
    let artifacts = try artifactPaths()
    Output.error("[1/5] verifying capability profile")
    let comparison = try MetalProbeRunner().compare(profile: selected, artifacts: artifacts)
    guard comparison.changedOnlyExpectedCapabilities else {
      throw ValidationError("capability probe changed values outside the selected profile")
    }
    guard
      allowPhysicalHost
        || comparison.stock.device.localizedCaseInsensitiveContains("paravirtual")
    else {
      throw ValidationError(
        "refusing certification on physical device `\(comparison.stock.device)`; run inside the macOS guest"
      )
    }

    let arguments = [
      "-m", modelURL.path,
      "-p", String(promptTokens),
      "-n", String(generationTokens),
      "-r", String(repetitions),
      "-t", String(threads),
      "-ngl", "-1",
      "-o", "json",
    ]
    let runner = CommandRunner()

    Output.error("[2/5] running stock llama.cpp benchmark")
    let stockExecution = try execute(
      runner: runner,
      executable: benchURL,
      arguments: arguments,
      environment: nil
    )
    guard !stockExecution.stderr.contains("[LunchpailMetal] Enabled") else {
      throw MetalBenchmarkError.shimUnexpectedlyLoadedInStockRun
    }
    let stock = try LlamaBenchmarkSummary(jsonData: Data(stockExecution.stdout.utf8))

    Output.error("[3/5] running profiled llama.cpp benchmark")
    let profileEnvironment = try selected.environment(shimURL: artifacts.shimURL)
    let profiledExecution = try execute(
      runner: runner,
      executable: benchURL,
      arguments: arguments,
      environment: profileEnvironment
    )
    guard profiledExecution.stderr.contains("[LunchpailMetal] Enabled") else {
      throw MetalBenchmarkError.shimNotObserved
    }
    let profiled = try LlamaBenchmarkSummary(jsonData: Data(profiledExecution.stdout.utf8))

    Output.error("[4/5] hashing benchmark artifacts")
    let digests = try [
      ArtifactDigest(role: "llama-bench", url: benchURL),
      ArtifactDigest(role: "model", url: modelURL),
      ArtifactDigest(role: "metal-probe", url: artifacts.probeURL),
      ArtifactDigest(role: "metal-shim", url: artifacts.shimURL),
    ]
    let certification = MetalLlamaCertification(
      recordedAt: ISO8601DateFormatter().string(from: Date()),
      system: try systemFingerprint(runner: runner),
      profileID: profile,
      capabilityProbe: comparison,
      artifacts: digests,
      arguments: arguments,
      stock: stock,
      profiled: profiled,
      minimumPromptSpeedup: minimumPromptSpeedup,
      minimumGenerationSpeedup: minimumGenerationSpeedup
    )

    Output.error("[5/5] writing certification record")
    if let output {
      let outputURL = URL(fileURLWithPath: output).standardizedFileURL
      let data = try JSONEncoder.stable.encode(certification)
      try data.write(to: outputURL, options: [.atomic])
      Output.error("wrote \(outputURL.path)")
    } else {
      try Output.json(certification)
    }

    let prompt = String(format: "%.2f", certification.promptSpeedup)
    let generation = String(format: "%.2f", certification.generationSpeedup)
    Output.error("prompt speedup: \(prompt)x; generation speedup: \(generation)x")
    guard certification.passed else {
      for failure in certification.validationFailures {
        Output.error("failed: \(failure)")
      }
      throw ExitCode.failure
    }
    Output.error("certification passed")
  }

  private func artifactPaths() throws -> MetalArtifactPaths {
    if let probePath, let shimPath {
      return MetalArtifactPaths(
        probeURL: URL(fileURLWithPath: probePath).standardizedFileURL,
        shimURL: URL(fileURLWithPath: shimPath).standardizedFileURL
      )
    }
    guard probePath == nil, shimPath == nil else {
      throw ValidationError("provide both --probe-path and --shim-path, or neither")
    }
    return try .adjacentToExecutable()
  }

  private func execute(
    runner: CommandRunner,
    executable: URL,
    arguments: [String],
    environment: [String: String]?
  ) throws -> CommandResult {
    try runner.checkedRun(
      executable: executable,
      arguments: arguments,
      environment: environment
    )
  }

  private func systemFingerprint(runner: CommandRunner) throws -> CertificationSystem {
    CertificationSystem(
      chip: try output(runner, "/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]),
      architecture: try output(runner, "/usr/bin/uname", ["-m"]),
      productVersion: try output(runner, "/usr/bin/sw_vers", ["-productVersion"]),
      buildVersion: try output(runner, "/usr/bin/sw_vers", ["-buildVersion"])
    )
  }

  private func output(_ runner: CommandRunner, _ executable: String, _ arguments: [String]) throws
    -> String
  {
    let result = try runner.checkedRun(
      executable: URL(fileURLWithPath: executable),
      arguments: arguments
    )
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum MetalBenchmarkError: LocalizedError, Equatable {
  case shimNotObserved
  case shimUnexpectedlyLoadedInStockRun

  var errorDescription: String? {
    switch self {
    case .shimNotObserved:
      return "profiled workload did not report that the Lunchpail Metal shim loaded"
    case .shimUnexpectedlyLoadedInStockRun:
      return "stock workload unexpectedly loaded the Lunchpail Metal shim"
    }
  }
}
