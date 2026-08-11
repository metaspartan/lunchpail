import Foundation
import Testing
import Virtualization

@testable import LunchpailCore

@Test func rejectsNonMacOSLumeConfig() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-lume-import-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let config: [String: Any] = [
    "os": "linux",
    "hardwareModel": "unused",
    "machineIdentifier": "unused",
  ]
  let data = try JSONSerialization.data(withJSONObject: config)
  try data.write(to: directory.appendingPathComponent("config.json"))

  #expect(throws: LumeImportError.notMacOS("linux")) {
    _ = try LumeVMImporter().importManifest(from: directory)
  }
}
