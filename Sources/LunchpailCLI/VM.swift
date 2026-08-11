import ArgumentParser

struct VM: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create, inspect, clone, and run virtual machines.",
    subcommands: [
      VMList.self,
      VMInfo.self,
      VMAdd.self,
      VMRemove.self,
      VMCreate.self,
      VMImportLume.self,
      VMClone.self,
      VMValidate.self,
      VMStart.self,
      VMStop.self,
      VMStatus.self,
      VMRun.self,
    ]
  )
}
