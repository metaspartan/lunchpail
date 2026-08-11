import Darwin
import Foundation
import Virtualization

public struct VMDisplay: Codable, Equatable, Sendable {
  public var widthPixels: Int
  public var heightPixels: Int
  public var pixelsPerInch: Int

  public init(widthPixels: Int = 1920, heightPixels: Int = 1200, pixelsPerInch: Int = 144) {
    self.widthPixels = widthPixels
    self.heightPixels = heightPixels
    self.pixelsPerInch = pixelsPerInch
  }
}

public struct VMManifest: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var name: String
  public var cpuCount: Int
  public var memoryBytes: UInt64
  public var diskPath: String
  public var auxiliaryStoragePath: String
  public var hardwareModelBase64: String
  public var machineIdentifierBase64: String
  public var macAddress: String
  public var display: VMDisplay
  public var sharedDirectoryPath: String?
  public var metalProfileID: String

  public init(
    schemaVersion: Int = 1,
    name: String,
    cpuCount: Int,
    memoryBytes: UInt64,
    diskPath: String,
    auxiliaryStoragePath: String,
    hardwareModelBase64: String,
    machineIdentifierBase64: String,
    macAddress: String = VZMACAddress.randomLocallyAdministered().string,
    display: VMDisplay = VMDisplay(),
    sharedDirectoryPath: String? = nil,
    metalProfileID: String = "stock"
  ) {
    self.schemaVersion = schemaVersion
    self.name = name
    self.cpuCount = cpuCount
    self.memoryBytes = memoryBytes
    self.diskPath = diskPath
    self.auxiliaryStoragePath = auxiliaryStoragePath
    self.hardwareModelBase64 = hardwareModelBase64
    self.machineIdentifierBase64 = machineIdentifierBase64
    self.macAddress = macAddress
    self.display = display
    self.sharedDirectoryPath = sharedDirectoryPath
    self.metalProfileID = metalProfileID
  }

  public static func load(from url: URL) throws -> VMManifest {
    try JSONDecoder().decode(VMManifest.self, from: Data(contentsOf: url))
  }

  public func write(to url: URL) throws {
    let data = try JSONEncoder.stable.encode(self)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }

  public func validate(baseURL: URL, requireFiles: Bool = true) throws {
    guard schemaVersion == 1 else { throw VMManifestError.unsupportedSchema(schemaVersion) }
    guard Self.isValidName(name) else { throw VMManifestError.invalidName(name) }
    guard (1...VZVirtualMachineConfiguration.maximumAllowedCPUCount).contains(cpuCount) else {
      throw VMManifestError.invalidCPUCount(cpuCount)
    }
    guard memoryBytes >= VZVirtualMachineConfiguration.minimumAllowedMemorySize,
      memoryBytes <= VZVirtualMachineConfiguration.maximumAllowedMemorySize,
      memoryBytes.isMultiple(of: 1_048_576)
    else {
      throw VMManifestError.invalidMemorySize(memoryBytes)
    }
    guard (640...8192).contains(display.widthPixels),
      (480...8192).contains(display.heightPixels),
      (36...600).contains(display.pixelsPerInch)
    else {
      throw VMManifestError.invalidDisplay(display)
    }
    guard VZMACAddress(string: macAddress) != nil else {
      throw VMManifestError.invalidMACAddress(macAddress)
    }
    guard let hardwareData = Data(base64Encoded: hardwareModelBase64),
      VZMacHardwareModel(dataRepresentation: hardwareData) != nil
    else {
      throw VMManifestError.invalidHardwareModel
    }
    guard let identifierData = Data(base64Encoded: machineIdentifierBase64),
      VZMacMachineIdentifier(dataRepresentation: identifierData) != nil
    else {
      throw VMManifestError.invalidMachineIdentifier
    }
    _ = try MetalProfileRegistry.profile(id: metalProfileID)

    let diskURL = try bundleURL(for: diskPath, baseURL: baseURL)
    let auxiliaryURL = try bundleURL(for: auxiliaryStoragePath, baseURL: baseURL)
    let sharedURL = try sharedDirectoryPath.map { try bundleURL(for: $0, baseURL: baseURL) }

    if requireFiles {
      for url in [diskURL, auxiliaryURL] {
        try Self.requireResource(url, type: S_IFREG)
      }
      if let sharedURL {
        try Self.requireResource(sharedURL, type: S_IFDIR)
      }
    }
  }

  public func bundleURL(for path: String, baseURL: URL) throws -> URL {
    guard !path.isEmpty, !NSString(string: path).isAbsolutePath else {
      throw VMManifestError.resourcePathMustBeRelative(path)
    }
    let canonicalBase = baseURL.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = canonicalBase.appendingPathComponent(path).standardizedFileURL
      .resolvingSymlinksInPath()
    let prefix = canonicalBase.path.hasSuffix("/") ? canonicalBase.path : canonicalBase.path + "/"
    guard candidate.path.hasPrefix(prefix) else {
      throw VMManifestError.resourceOutsideBundle(path)
    }
    return candidate
  }

  public static func isValidName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= 63 else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    guard name.unicodeScalars.allSatisfy(allowed.contains) else { return false }
    return name.first?.isLetter == true || name.first?.isNumber == true
  }

  private static func requireResource(_ url: URL, type: mode_t) throws {
    var status = stat()
    guard lstat(url.path, &status) == 0 else {
      if type == S_IFDIR {
        throw VMManifestError.missingDirectory(url.path)
      }
      throw VMManifestError.missingFile(url.path)
    }
    guard status.st_mode & S_IFMT == type, status.st_uid == getuid() else {
      throw VMManifestError.invalidResource(url.path)
    }
  }
}

public enum VMManifestError: LocalizedError, Equatable {
  case unsupportedSchema(Int)
  case invalidName(String)
  case invalidCPUCount(Int)
  case invalidMemorySize(UInt64)
  case invalidDisplay(VMDisplay)
  case invalidMACAddress(String)
  case invalidHardwareModel
  case invalidMachineIdentifier
  case unsupportedHardwareModel
  case missingFile(String)
  case missingDirectory(String)
  case resourcePathMustBeRelative(String)
  case resourceOutsideBundle(String)
  case invalidResource(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version): return "unsupported VM manifest schema: \(version)"
    case .invalidName(let name): return "invalid VM name: \(name)"
    case .invalidCPUCount(let count): return "invalid VM CPU count: \(count)"
    case .invalidMemorySize(let bytes): return "invalid VM memory size: \(bytes) bytes"
    case .invalidDisplay(let display):
      return
        "invalid display: \(display.widthPixels)x\(display.heightPixels) at \(display.pixelsPerInch) ppi"
    case .invalidMACAddress(let address): return "invalid MAC address: \(address)"
    case .invalidHardwareModel:
      return "hardwareModelBase64 is not a VZMacHardwareModel representation"
    case .invalidMachineIdentifier:
      return "machineIdentifierBase64 is not a VZMacMachineIdentifier representation"
    case .unsupportedHardwareModel: return "this host does not support the VM's hardware model"
    case .missingFile(let path): return "required VM file is missing: \(path)"
    case .missingDirectory(let path): return "shared directory is missing: \(path)"
    case .resourcePathMustBeRelative(let path):
      return "VM resource path must be relative to its bundle: \(path)"
    case .resourceOutsideBundle(let path):
      return "VM resource path escapes its bundle: \(path)"
    case .invalidResource(let path):
      return "VM resource is not an owner-controlled regular file or directory: \(path)"
    }
  }
}
