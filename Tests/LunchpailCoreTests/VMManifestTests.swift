import Foundation
import Testing

@testable import LunchpailCore

@Test func invalidNameFailsBeforeTouchingVMFiles() throws {
  let manifest = VMManifest(
    name: "../../escape",
    cpuCount: 4,
    memoryBytes: 4 * 1_024 * 1_024 * 1_024,
    diskPath: "disk.asif",
    auxiliaryStoragePath: "auxiliary-storage",
    hardwareModelBase64: "bad",
    machineIdentifierBase64: "bad"
  )

  #expect(throws: VMManifestError.invalidName("../../escape")) {
    try manifest.validate(baseURL: FileManager.default.temporaryDirectory, requireFiles: false)
  }
}

@Test func relativePathsResolveUnderManifestDirectory() throws {
  let manifest = VMManifest(
    name: "worker-1",
    cpuCount: 4,
    memoryBytes: 4 * 1_024 * 1_024 * 1_024,
    diskPath: "images/disk.asif",
    auxiliaryStoragePath: "auxiliary-storage",
    hardwareModelBase64: "unused",
    machineIdentifierBase64: "unused"
  )
  let base = URL(fileURLWithPath: "/tmp/lunchpail-vm", isDirectory: true)
  #expect(
    try manifest.bundleURL(for: manifest.diskPath, baseURL: base).path
      == "/tmp/lunchpail-vm/images/disk.asif")
}

@Test func resourcePathsCannotEscapeBundle() throws {
  let manifest = VMManifest(
    name: "worker-1",
    cpuCount: 4,
    memoryBytes: 4 * 1_024 * 1_024 * 1_024,
    diskPath: "disk.img",
    auxiliaryStoragePath: "nvram.bin",
    hardwareModelBase64: "unused",
    machineIdentifierBase64: "unused"
  )
  let base = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-manifest-path-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: base) }

  #expect(throws: VMManifestError.resourcePathMustBeRelative("/tmp/disk.img")) {
    _ = try manifest.bundleURL(for: "/tmp/disk.img", baseURL: base)
  }
  #expect(throws: VMManifestError.resourceOutsideBundle("../disk.img")) {
    _ = try manifest.bundleURL(for: "../disk.img", baseURL: base)
  }
}

@Test func symlinkedResourceCannotEscapeBundle() throws {
  let manifest = VMManifest(
    name: "worker-1",
    cpuCount: 4,
    memoryBytes: 4 * 1_024 * 1_024 * 1_024,
    diskPath: "disk.img",
    auxiliaryStoragePath: "nvram.bin",
    hardwareModelBase64: "unused",
    machineIdentifierBase64: "unused"
  )
  let base = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-manifest-symlink-\(UUID().uuidString)", isDirectory: true)
  let outside = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-manifest-outside-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  try Data().write(to: outside.appendingPathComponent("disk.img"))
  defer {
    try? FileManager.default.removeItem(at: base)
    try? FileManager.default.removeItem(at: outside)
  }
  let link = base.appendingPathComponent("escape", isDirectory: true)
  try FileManager.default.createSymbolicLink(
    at: link,
    withDestinationURL: outside
  )

  #expect(throws: VMManifestError.resourceOutsideBundle("escape/disk.img")) {
    _ = try manifest.bundleURL(for: "escape/disk.img", baseURL: base)
  }
}

@Test func manifestWritesOwnerOnlyFile() throws {
  let manifest = VMManifest(
    name: "worker-1",
    cpuCount: 4,
    memoryBytes: 4 * 1_024 * 1_024 * 1_024,
    diskPath: "disk.img",
    auxiliaryStoragePath: "nvram.bin",
    hardwareModelBase64: "unused",
    machineIdentifierBase64: "unused"
  )
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-manifest-mode-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: url) }

  try manifest.write(to: url)
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
