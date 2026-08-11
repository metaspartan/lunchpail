import Darwin
import Foundation
import Virtualization

public struct VMCloneReport: Codable, Equatable, Sendable {
  public let sourceManifestPath: String
  public let destinationManifestPath: String
  public let usedCopyOnWrite: Bool
  public let logicalDiskBytes: UInt64
  public let elapsedSeconds: Double
}

public struct VMCloner: Sendable {
  public init() {}

  public func clone(
    sourceManifestURL: URL,
    destinationDirectoryURL: URL,
    name: String,
    allowFullCopy: Bool = false
  ) throws -> VMCloneReport {
    let sourceManifestURL = sourceManifestURL.standardizedFileURL.resolvingSymlinksInPath()
    let sourceDirectory = sourceManifestURL.deletingLastPathComponent()
    let rawDestination = destinationDirectoryURL.standardizedFileURL
    let destinationDirectory = rawDestination.deletingLastPathComponent()
      .resolvingSymlinksInPath()
      .appendingPathComponent(rawDestination.lastPathComponent, isDirectory: true)
    guard sourceDirectory != destinationDirectory else {
      throw VMCloneError.sourceEqualsDestination
    }
    guard !destinationDirectory.path.hasPrefix(sourceDirectory.path + "/") else {
      throw VMCloneError.destinationInsideSource(destinationDirectory.path)
    }
    guard !FileManager.default.fileExists(atPath: destinationDirectory.path) else {
      throw VMCloneError.destinationExists(destinationDirectory.path)
    }

    let sourceLock = try VMDirectoryLock(directoryURL: sourceDirectory, mode: .shared)
    defer { withExtendedLifetime(sourceLock) {} }
    let source = try VMManifest.load(from: sourceManifestURL)
    try source.validate(baseURL: sourceDirectory)

    let parent = destinationDirectory.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(
      ".\(destinationDirectory.lastPathComponent).lunchpail-clone-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
    var committed = false
    defer {
      if !committed { try? FileManager.default.removeItem(at: staging) }
    }

    let startedAt = Date()
    let sourceDisk = try source.bundleURL(for: source.diskPath, baseURL: sourceDirectory)
    let sourceAuxiliary = try source.bundleURL(
      for: source.auxiliaryStoragePath,
      baseURL: sourceDirectory
    )
    let diskName = sourceDisk.lastPathComponent
    let auxiliaryName = sourceAuxiliary.lastPathComponent
    guard diskName != auxiliaryName else {
      throw VMCloneError.duplicateFileName(diskName)
    }

    let clone = VMManifest(
      name: name,
      cpuCount: source.cpuCount,
      memoryBytes: source.memoryBytes,
      diskPath: diskName,
      auxiliaryStoragePath: auxiliaryName,
      hardwareModelBase64: source.hardwareModelBase64,
      machineIdentifierBase64: VZMacMachineIdentifier().dataRepresentation.base64EncodedString(),
      macAddress: VZMACAddress.randomLocallyAdministered().string,
      display: source.display,
      sharedDirectoryPath: nil,
      metalProfileID: source.metalProfileID
    )
    try clone.validate(baseURL: staging, requireFiles: false)

    let diskWasCloned = try cloneFile(
      source: sourceDisk,
      destination: staging.appendingPathComponent(diskName),
      allowFullCopy: allowFullCopy
    )
    let auxiliaryWasCloned = try cloneFile(
      source: sourceAuxiliary,
      destination: staging.appendingPathComponent(auxiliaryName),
      allowFullCopy: allowFullCopy
    )
    try setPrivateFileMode(staging.appendingPathComponent(diskName))
    try setPrivateFileMode(staging.appendingPathComponent(auxiliaryName))
    let manifestURL = staging.appendingPathComponent("lunchpail.json")
    try clone.write(to: manifestURL)
    try clone.validate(baseURL: staging)
    try FileManager.default.moveItem(at: staging, to: destinationDirectory)
    committed = true

    let attributes = try FileManager.default.attributesOfItem(atPath: sourceDisk.path)
    return VMCloneReport(
      sourceManifestPath: sourceManifestURL.path,
      destinationManifestPath:
        destinationDirectory
        .appendingPathComponent("lunchpail.json").path,
      usedCopyOnWrite: diskWasCloned && auxiliaryWasCloned,
      logicalDiskBytes: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
      elapsedSeconds: Date().timeIntervalSince(startedAt)
    )
  }

  private func cloneFile(
    source: URL,
    destination: URL,
    allowFullCopy: Bool
  ) throws -> Bool {
    if Darwin.clonefile(source.path, destination.path, 0) == 0 {
      return true
    }
    let cloneErrno = errno
    guard allowFullCopy else {
      throw VMCloneError.copyOnWriteUnavailable(
        source.path,
        cloneErrno,
        String(cString: strerror(cloneErrno))
      )
    }
    try FileManager.default.copyItem(at: source, to: destination)
    return false
  }

  private func setPrivateFileMode(_ url: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

public enum VMCloneError: LocalizedError, Equatable {
  case sourceEqualsDestination
  case destinationInsideSource(String)
  case destinationExists(String)
  case duplicateFileName(String)
  case copyOnWriteUnavailable(String, Int32, String)

  public var errorDescription: String? {
    switch self {
    case .sourceEqualsDestination:
      return "source and destination VM directories are the same"
    case .destinationInsideSource(let path):
      return "destination VM directory cannot be inside the source VM: \(path)"
    case .destinationExists(let path):
      return "destination VM directory already exists: \(path)"
    case .duplicateFileName(let name):
      return "the source disk and auxiliary storage use the same file name: \(name)"
    case .copyOnWriteUnavailable(let path, let errno, let detail):
      return
        "copy-on-write clone unavailable for \(path) (errno \(errno): \(detail)); pass --allow-full-copy to permit a potentially large copy"
    }
  }
}
