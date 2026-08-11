import Foundation
import Testing

@testable import LunchpailCore

@Test func clonerRejectsDestinationInsideSourceBeforeReadingManifest() throws {
  let source = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-clone-source-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: source) }

  let manifest = source.appendingPathComponent("missing.json")
  let nestedDestination = source.appendingPathComponent("clone", isDirectory: true)

  #expect(throws: VMCloneError.destinationInsideSource(nestedDestination.path)) {
    _ = try VMCloner().clone(
      sourceManifestURL: manifest,
      destinationDirectoryURL: nestedDestination,
      name: "clone"
    )
  }
}

@Test func clonerRejectsSourceAsDestinationBeforeReadingManifest() throws {
  let source = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-clone-source-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: source) }

  #expect(throws: VMCloneError.sourceEqualsDestination) {
    _ = try VMCloner().clone(
      sourceManifestURL: source.appendingPathComponent("missing.json"),
      destinationDirectoryURL: source,
      name: "clone"
    )
  }
}
