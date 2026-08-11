import Foundation
import Virtualization

public struct LumeVMImporter: Sendable {
  public init() {}

  public func importManifest(
    from directoryURL: URL,
    name: String? = nil,
    metalProfileID: String = "stock"
  ) throws -> VMManifest {
    let configURL = directoryURL.appendingPathComponent("config.json")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL))
    guard let config = object as? [String: Any] else {
      throw LumeImportError.invalidConfig(configURL.path)
    }
    let os = config["os"] as? String
    guard os?.localizedCaseInsensitiveContains("mac") == true else {
      throw LumeImportError.notMacOS(os ?? "<missing>")
    }
    guard let hardwareModel = config["hardwareModel"] as? String else {
      throw LumeImportError.missingField("hardwareModel")
    }
    guard let machineIdentifier = config["machineIdentifier"] as? String else {
      throw LumeImportError.missingField("machineIdentifier")
    }

    let display = parseDisplay(config["display"] as? String ?? "1920x1200")
    let manifest = VMManifest(
      name: name ?? directoryURL.lastPathComponent,
      cpuCount: integer(config["cpuCount"]) ?? min(ProcessInfo.processInfo.processorCount, 8),
      memoryBytes: unsignedInteger(config["memorySize"]) ?? 16 * 1_024 * 1_024 * 1_024,
      diskPath: "disk.img",
      auxiliaryStoragePath: "nvram.bin",
      hardwareModelBase64: hardwareModel,
      machineIdentifierBase64: machineIdentifier,
      macAddress: config["macAddress"] as? String
        ?? VZMACAddress.randomLocallyAdministered().string,
      display: display,
      metalProfileID: metalProfileID
    )
    try manifest.validate(baseURL: directoryURL)
    return manifest
  }

  private func parseDisplay(_ raw: String) -> VMDisplay {
    let dimensions = raw.split(separator: "@", maxSplits: 1).first ?? Substring(raw)
    let parts = dimensions.lowercased().split(separator: "x", maxSplits: 1)
    guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else {
      return VMDisplay()
    }
    return VMDisplay(widthPixels: width, heightPixels: height, pixelsPerInch: 144)
  }

  private func integer(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
  }

  private func unsignedInteger(_ value: Any?) -> UInt64? {
    (value as? NSNumber)?.uint64Value
  }
}

public enum LumeImportError: LocalizedError, Equatable {
  case invalidConfig(String)
  case notMacOS(String)
  case missingField(String)

  public var errorDescription: String? {
    switch self {
    case .invalidConfig(let path): return "invalid Lume configuration: \(path)"
    case .notMacOS(let os): return "Lume VM is not a macOS guest: \(os)"
    case .missingField(let field): return "Lume configuration is missing \(field)"
    }
  }
}
