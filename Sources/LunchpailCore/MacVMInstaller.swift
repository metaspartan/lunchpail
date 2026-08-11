import Foundation
import Virtualization

public struct MacVMInstallRequest: Sendable {
  public let name: String
  public let destinationDirectoryURL: URL
  public let restoreImageURL: URL
  public let cpuCount: Int
  public let memoryBytes: UInt64
  public let diskBytes: UInt64
  public let display: VMDisplay
  public let metalProfileID: String

  public init(
    name: String,
    destinationDirectoryURL: URL,
    restoreImageURL: URL,
    cpuCount: Int,
    memoryBytes: UInt64,
    diskBytes: UInt64,
    display: VMDisplay = VMDisplay(),
    metalProfileID: String = "stock"
  ) {
    self.name = name
    self.destinationDirectoryURL = destinationDirectoryURL
    self.restoreImageURL = restoreImageURL
    self.cpuCount = cpuCount
    self.memoryBytes = memoryBytes
    self.diskBytes = diskBytes
    self.display = display
    self.metalProfileID = metalProfileID
  }
}

public struct MacVMInstallReport: Codable, Equatable, Sendable {
  public let name: String
  public let manifestPath: String
  public let operatingSystemVersion: String
  public let buildVersion: String
  public let diskBytes: UInt64
  public let elapsedSeconds: Double
}

@MainActor
public struct MacVMInstaller {
  public init() {}

  public func install(
    _ request: MacVMInstallRequest,
    progress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> MacVMInstallReport {
    try validate(request)
    let restoreImage = try await VZMacOSRestoreImage.image(from: request.restoreImageURL)
    guard restoreImage.isSupported,
      let requirements = restoreImage.mostFeaturefulSupportedConfiguration
    else {
      throw MacVMInstallError.unsupportedRestoreImage(request.restoreImageURL.path)
    }
    guard request.cpuCount >= requirements.minimumSupportedCPUCount else {
      throw MacVMInstallError.insufficientCPU(
        requested: request.cpuCount,
        minimum: requirements.minimumSupportedCPUCount
      )
    }
    guard request.memoryBytes >= requirements.minimumSupportedMemorySize else {
      throw MacVMInstallError.insufficientMemory(
        requested: request.memoryBytes,
        minimum: requirements.minimumSupportedMemorySize
      )
    }

    let destination = request.destinationDirectoryURL.standardizedFileURL
    let parent = destination.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(
      ".\(destination.lastPathComponent).lunchpail-install-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
    var committed = false
    defer {
      if !committed { try? FileManager.default.removeItem(at: staging) }
    }

    let diskURL = staging.appendingPathComponent("disk.img")
    let auxiliaryURL = staging.appendingPathComponent("nvram.bin")
    try createSparseFile(at: diskURL, size: request.diskBytes)
    let auxiliaryStorage = try VZMacAuxiliaryStorage(
      creatingStorageAt: auxiliaryURL,
      hardwareModel: requirements.hardwareModel,
      options: []
    )
    try setPrivateFileMode(auxiliaryURL)
    let machineIdentifier = VZMacMachineIdentifier()
    let manifest = VMManifest(
      name: request.name,
      cpuCount: request.cpuCount,
      memoryBytes: request.memoryBytes,
      diskPath: diskURL.lastPathComponent,
      auxiliaryStoragePath: auxiliaryURL.lastPathComponent,
      hardwareModelBase64: requirements.hardwareModel.dataRepresentation.base64EncodedString(),
      machineIdentifierBase64: machineIdentifier.dataRepresentation.base64EncodedString(),
      display: request.display,
      metalProfileID: request.metalProfileID
    )
    let manifestURL = staging.appendingPathComponent("lunchpail.json")
    try manifest.write(to: manifestURL)
    let configuration = try MacVMConfigurationBuilder.build(
      manifest: manifest,
      baseURL: staging
    )
    if let platform = configuration.platform as? VZMacPlatformConfiguration {
      platform.auxiliaryStorage = auxiliaryStorage
      platform.machineIdentifier = machineIdentifier
    }
    try configuration.validate()

    let startedAt = Date()
    let virtualMachine = VZVirtualMachine(configuration: configuration)
    let installer = VZMacOSInstaller(
      virtualMachine: virtualMachine,
      restoringFromImageAt: request.restoreImageURL
    )
    let observation = installer.progress.observe(
      \.fractionCompleted,
      options: [.initial, .new]
    ) { current, _ in
      progress(current.fractionCompleted)
    }
    defer { observation.invalidate() }
    try await installer.install()

    try setPrivateFileMode(diskURL)
    try setPrivateFileMode(auxiliaryURL)
    try setPrivateFileMode(manifestURL)
    try manifest.validate(baseURL: staging)
    try FileManager.default.moveItem(at: staging, to: destination)
    committed = true
    let version = restoreImage.operatingSystemVersion
    return MacVMInstallReport(
      name: request.name,
      manifestPath: destination.appendingPathComponent("lunchpail.json").path,
      operatingSystemVersion:
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      buildVersion: restoreImage.buildVersion,
      diskBytes: request.diskBytes,
      elapsedSeconds: Date().timeIntervalSince(startedAt)
    )
  }

  private func validate(_ request: MacVMInstallRequest) throws {
    guard VMManifest.isValidName(request.name) else {
      throw VMManifestError.invalidName(request.name)
    }
    guard !FileManager.default.fileExists(atPath: request.destinationDirectoryURL.path) else {
      throw MacVMInstallError.destinationExists(request.destinationDirectoryURL.path)
    }
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: request.restoreImageURL.path,
        isDirectory: &isDirectory
      ), !isDirectory.boolValue
    else {
      throw MacVMInstallError.missingRestoreImage(request.restoreImageURL.path)
    }
    guard request.diskBytes >= 64 * 1_024 * 1_024 * 1_024,
      request.diskBytes.isMultiple(of: 1_048_576)
    else {
      throw MacVMInstallError.invalidDiskSize(request.diskBytes)
    }
    _ = try MetalProfileRegistry.profile(id: request.metalProfileID)
    let provisional = VMManifest(
      name: request.name,
      cpuCount: request.cpuCount,
      memoryBytes: request.memoryBytes,
      diskPath: "disk.img",
      auxiliaryStoragePath: "nvram.bin",
      hardwareModelBase64: "",
      machineIdentifierBase64: "",
      display: request.display,
      metalProfileID: request.metalProfileID
    )
    guard
      (1...VZVirtualMachineConfiguration.maximumAllowedCPUCount).contains(
        provisional.cpuCount
      )
    else {
      throw VMManifestError.invalidCPUCount(provisional.cpuCount)
    }
    guard provisional.memoryBytes >= VZVirtualMachineConfiguration.minimumAllowedMemorySize,
      provisional.memoryBytes <= VZVirtualMachineConfiguration.maximumAllowedMemorySize,
      provisional.memoryBytes.isMultiple(of: 1_048_576)
    else {
      throw VMManifestError.invalidMemorySize(provisional.memoryBytes)
    }
  }

  private func createSparseFile(at url: URL, size: UInt64) throws {
    guard
      FileManager.default.createFile(
        atPath: url.path,
        contents: nil,
        attributes: [.posixPermissions: 0o600]
      )
    else {
      throw MacVMInstallError.cannotCreateDisk(url.path)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: size)
  }

  private func setPrivateFileMode(_ url: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

public enum MacVMInstallError: LocalizedError, Equatable {
  case destinationExists(String)
  case missingRestoreImage(String)
  case unsupportedRestoreImage(String)
  case invalidDiskSize(UInt64)
  case insufficientCPU(requested: Int, minimum: Int)
  case insufficientMemory(requested: UInt64, minimum: UInt64)
  case cannotCreateDisk(String)

  public var errorDescription: String? {
    switch self {
    case .destinationExists(let path): return "destination VM directory already exists: \(path)"
    case .missingRestoreImage(let path): return "macOS restore image is missing: \(path)"
    case .unsupportedRestoreImage(let path):
      return "macOS restore image is not supported on this host: \(path)"
    case .invalidDiskSize(let bytes):
      return "macOS disk must be at least 64 GiB and MiB-aligned: \(bytes) bytes"
    case .insufficientCPU(let requested, let minimum):
      return "restore image needs at least \(minimum) CPUs; \(requested) requested"
    case .insufficientMemory(let requested, let minimum):
      return "restore image needs at least \(minimum) bytes of memory; \(requested) requested"
    case .cannotCreateDisk(let path): return "could not create VM disk: \(path)"
    }
  }
}
