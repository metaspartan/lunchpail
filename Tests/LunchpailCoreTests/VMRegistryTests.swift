import Foundation
import Testing

@testable import LunchpailCore

@Test func registryDiscoversResolvesAndExcludesManifest() throws {
  let temporary = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-registry-\(UUID().uuidString)", isDirectory: true)
  let root = temporary.appendingPathComponent("state", isDirectory: true)
  let lume = temporary.appendingPathComponent("lume", isDirectory: true)
  let vm = lume.appendingPathComponent("sample", isDirectory: true)
  try FileManager.default.createDirectory(at: vm, withIntermediateDirectories: true)
  try Data("{}".utf8).write(to: vm.appendingPathComponent("lunchpail.json"))
  defer { try? FileManager.default.removeItem(at: temporary) }

  let registry = VMRegistry(rootURL: root, lumeDirectoryURL: lume)
  let listed = try registry.list()
  #expect(listed.count == 1)
  #expect(listed[0].name == "sample")
  #expect(!listed[0].isValid)
  #expect(try registry.resolve(listed[0].id) == listed[0])
  #expect(try registry.resolve("sample") == listed[0])
  #expect(try registry.resolve(vm.path) == listed[0])

  let removed = try registry.unregister(listed[0].id)
  #expect(removed == listed[0])
  #expect(try registry.list().isEmpty)
}

@Test func registryReportsAmbiguousNames() throws {
  let temporary = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-registry-\(UUID().uuidString)", isDirectory: true)
  let root = temporary.appendingPathComponent("state", isDirectory: true)
  let lume = temporary.appendingPathComponent("lume", isDirectory: true)
  let managed = root.appendingPathComponent("VMs/sample", isDirectory: true)
  let imported = lume.appendingPathComponent("sample", isDirectory: true)
  for directory in [managed, imported] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: directory.appendingPathComponent("lunchpail.json"))
  }
  defer { try? FileManager.default.removeItem(at: temporary) }

  let registry = VMRegistry(rootURL: root, lumeDirectoryURL: lume)
  let identifiers = try registry.list().map(\.id)
  #expect(throws: VMRegistryError.ambiguousSelector("sample", identifiers)) {
    _ = try registry.resolve("sample")
  }
}
