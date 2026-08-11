import Foundation
import Testing

@testable import LunchpailCore

@Test func exclusiveVMLockRejectsConcurrentAccessAndReleases() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-lock-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  var owner: VMDirectoryLock? = try VMDirectoryLock(
    directoryURL: directory,
    mode: .exclusive
  )
  let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
  let lockAttributes = try FileManager.default.attributesOfItem(
    atPath: directory.appendingPathComponent(".lunchpail.lock").path
  )
  #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
  #expect((lockAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  #expect(throws: VMDirectoryLockError.busy(directory.path)) {
    _ = try VMDirectoryLock(directoryURL: directory, mode: .shared)
  }

  owner = nil
  _ = try VMDirectoryLock(directoryURL: directory, mode: .exclusive)
  #expect(owner == nil)
}
