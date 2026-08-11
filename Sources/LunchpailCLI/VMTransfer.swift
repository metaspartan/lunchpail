import ArgumentParser
import Foundation
import LunchpailCore

struct VMClone: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clone",
    abstract: "Atomically clone a stopped macOS VM with APFS copy-on-write."
  )

  @Argument(help: "Source VM ID, unique name, manifest path, or directory.")
  var manifest: String

  @Argument(help: "Destination VM directory, which must not exist.")
  var destination: String

  @Option(help: "New VM name. Defaults to the destination directory name.")
  var name: String?

  @Flag(help: "Permit a full disk copy when APFS copy-on-write is unavailable.")
  var allowFullCopy = false

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    let sourceURL = try VMRegistry().resolve(manifest).manifestURL
    let destinationURL = URL(
      fileURLWithPath: NSString(string: destination).expandingTildeInPath,
      isDirectory: true
    )
    .standardizedFileURL
    let report = try VMCloner().clone(
      sourceManifestURL: sourceURL,
      destinationDirectoryURL: destinationURL,
      name: name ?? destinationURL.lastPathComponent,
      allowFullCopy: allowFullCopy
    )
    _ = try VMRegistry().register(
      manifestURL: URL(fileURLWithPath: report.destinationManifestPath)
    )
    if json {
      try Output.json(report)
    } else {
      print("cloned VM to \(report.destinationManifestPath)")
      print("copy-on-write: \(report.usedCopyOnWrite ? "yes" : "no")")
      print(String(format: "elapsed: %.3f seconds", report.elapsedSeconds))
    }
  }
}

struct VMImportLume: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "import-lume",
    abstract: "Create a Lunchpail manifest for an existing Lume macOS VM without copying its disk."
  )

  @Argument(help: "Path to the Lume VM directory containing config.json, disk.img, and nvram.bin.")
  var directory: String

  @Option(help: "Output manifest path. Defaults to <directory>/lunchpail.json.")
  var output: String?

  @Option(help: "Metal profile metadata to record in the manifest.")
  var profile = "stock"

  mutating func run() throws {
    let directoryURL = URL(
      fileURLWithPath: NSString(string: directory).expandingTildeInPath,
      isDirectory: true
    ).standardizedFileURL
    let outputURL =
      output.map {
        URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath).standardizedFileURL
      }
      ?? directoryURL.appendingPathComponent("lunchpail.json")
    let manifest = try LumeVMImporter().importManifest(
      from: directoryURL,
      metalProfileID: profile
    )
    try manifest.write(to: outputURL)
    _ = try VMRegistry().register(manifestURL: outputURL)
    print("wrote Lunchpail VM manifest: \(outputURL.path)")
  }
}
