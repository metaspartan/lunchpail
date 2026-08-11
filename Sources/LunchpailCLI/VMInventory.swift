import ArgumentParser
import LunchpailCore

struct VMList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List known Lunchpail and imported Lume VMs.",
    aliases: ["ls"]
  )

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    let entries = try VMRegistry().list()
    if json {
      try Output.json(entries)
      return
    }
    guard !entries.isEmpty else {
      print("No VMs found. Import one with `lunchpail vm import-lume <directory>`.")
      return
    }
    for entry in entries {
      let state = entry.isValid ? "ready" : "invalid"
      print(
        "\(entry.id)  \(entry.name)  \(entry.cpuCount) CPU  \(Output.bytes(entry.memoryBytes))  \(entry.metalProfileID)  \(state)"
      )
    }
  }
}

struct VMInfo: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Show one VM by ID, name, manifest, or directory.",
    aliases: ["inspect"]
  )

  @Argument(help: "VM ID, unique name, manifest path, or VM directory.")
  var vm: String

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() throws {
    let entry = try VMRegistry().resolve(vm)
    if json {
      try Output.json(entry)
      return
    }
    print("id: \(entry.id)")
    print("name: \(entry.name)")
    print("manifest: \(entry.manifestPath)")
    print("resources: \(entry.cpuCount) CPU, \(Output.bytes(entry.memoryBytes))")
    print("Metal profile: \(entry.metalProfileID)")
    print("state: \(entry.isValid ? "ready" : "invalid")")
    if let validationError = entry.validationError {
      print("error: \(validationError)")
    }
  }
}

struct VMAdd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add",
    abstract: "Register an existing Lunchpail manifest.",
    aliases: ["register"]
  )

  @Argument(help: "Manifest path or VM directory.")
  var manifest: String

  mutating func run() throws {
    let url = VMRegistry.manifestURL(from: manifest)
    let entry = try VMRegistry().register(manifestURL: url)
    print("registered \(entry.name) as \(entry.id)")
  }
}

struct VMRemove: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove",
    abstract: "Forget a VM without deleting its files.",
    aliases: ["rm", "forget"]
  )

  @Argument(help: "VM ID, unique name, manifest path, or VM directory.")
  var vm: String

  mutating func run() throws {
    let entry = try VMRegistry().unregister(vm)
    print("forgot \(entry.name); files were not deleted")
  }
}
