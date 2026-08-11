import ArgumentParser

@main
struct Lunchpail: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lunchpail",
    abstract: "Metal-aware macOS VMs on Apple silicon.",
    version: "0.1.0-dev",
    subcommands: [Doctor.self, Metal.self, VM.self, API.self]
  )
}
