import CryptoKit
import Darwin
import Foundation

public struct VMInventoryEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let manifestPath: String
  public let cpuCount: Int
  public let memoryBytes: UInt64
  public let metalProfileID: String
  public let isValid: Bool
  public let validationError: String?

  public var manifestURL: URL {
    URL(fileURLWithPath: manifestPath)
  }
}

public struct VMRegistry: Sendable {
  public let rootURL: URL
  public let vmDirectoryURL: URL
  public let lumeDirectoryURL: URL

  private let registryURL: URL
  private let lockURL: URL

  public init(
    rootURL: URL? = nil,
    lumeDirectoryURL: URL? = nil
  ) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let root =
      rootURL
      ?? home.appendingPathComponent(
        "Library/Application Support/Lunchpail",
        isDirectory: true
      )
    self.rootURL = root.standardizedFileURL
    self.vmDirectoryURL = self.rootURL.appendingPathComponent("VMs", isDirectory: true)
    self.lumeDirectoryURL =
      (lumeDirectoryURL
      ?? home.appendingPathComponent(
        ".lume",
        isDirectory: true
      )).standardizedFileURL
    self.registryURL = self.rootURL.appendingPathComponent("registry.json")
    self.lockURL = self.rootURL.appendingPathComponent(".registry.lock")
  }

  public func list() throws -> [VMInventoryEntry] {
    try prepareRoot()
    let registry = try withRegistryLock { try loadRegistry() }
    let discovered =
      discoverManifests(in: vmDirectoryURL)
      + discoverManifests(in: lumeDirectoryURL)
    let paths = Set(registry.manifestPaths + discovered.map(\.path))
      .subtracting(registry.excludedManifestPaths)
    return paths.map { entry(for: URL(fileURLWithPath: $0)) }
      .sorted {
        if $0.name == $1.name { return $0.manifestPath < $1.manifestPath }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
  }

  @discardableResult
  public func register(manifestURL: URL) throws -> VMInventoryEntry {
    let canonical = canonicalManifestURL(manifestURL)
    let manifest = try VMManifest.load(from: canonical)
    let directory = canonical.deletingLastPathComponent()
    try manifest.validate(baseURL: directory)
    try hardenBundle(manifest: manifest, manifestURL: canonical, directory: directory)
    try prepareRoot()
    try withRegistryLock {
      var registry = try loadRegistry()
      if !registry.manifestPaths.contains(canonical.path) {
        registry.manifestPaths.append(canonical.path)
      }
      registry.excludedManifestPaths.removeAll { $0 == canonical.path }
      try writeRegistry(registry)
    }
    return entry(for: canonical)
  }

  @discardableResult
  public func unregister(_ selector: String) throws -> VMInventoryEntry {
    let selected = try resolve(selector)
    try prepareRoot()
    try withRegistryLock {
      var registry = try loadRegistry()
      registry.manifestPaths.removeAll { $0 == selected.manifestPath }
      if !registry.excludedManifestPaths.contains(selected.manifestPath) {
        registry.excludedManifestPaths.append(selected.manifestPath)
      }
      try writeRegistry(registry)
    }
    return selected
  }

  public func resolve(_ selector: String) throws -> VMInventoryEntry {
    let explicit = Self.manifestURL(from: selector)
    if FileManager.default.fileExists(atPath: explicit.path) {
      return entry(for: canonicalManifestURL(explicit))
    }

    let entries = try list()
    if let exactID = entries.first(where: { $0.id == selector }) {
      return exactID
    }
    let named = entries.filter { $0.name == selector }
    guard named.count <= 1 else {
      throw VMRegistryError.ambiguousSelector(selector, named.map(\.id))
    }
    guard let match = named.first else {
      throw VMRegistryError.notFound(selector)
    }
    return match
  }

  public static func manifestURL(from value: String) -> URL {
    let expanded = NSString(string: value).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return url }
    return url.appendingPathComponent("lunchpail.json")
  }

  public func entry(for manifestURL: URL) -> VMInventoryEntry {
    let canonical = canonicalManifestURL(manifestURL)
    let id = Self.identifier(for: canonical.path)
    do {
      let manifest = try VMManifest.load(from: canonical)
      try manifest.validate(baseURL: canonical.deletingLastPathComponent())
      return VMInventoryEntry(
        id: id,
        name: manifest.name,
        manifestPath: canonical.path,
        cpuCount: manifest.cpuCount,
        memoryBytes: manifest.memoryBytes,
        metalProfileID: manifest.metalProfileID,
        isValid: true,
        validationError: nil
      )
    } catch {
      return VMInventoryEntry(
        id: id,
        name: canonical.deletingLastPathComponent().lastPathComponent,
        manifestPath: canonical.path,
        cpuCount: 0,
        memoryBytes: 0,
        metalProfileID: "unknown",
        isValid: false,
        validationError: error.localizedDescription
      )
    }
  }

  private func prepareRoot() throws {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: vmDirectoryURL, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: vmDirectoryURL.path
    )
    if !FileManager.default.fileExists(atPath: lockURL.path) {
      guard
        FileManager.default.createFile(
          atPath: lockURL.path,
          contents: nil,
          attributes: [.posixPermissions: 0o600]
        )
      else {
        throw VMRegistryError.cannotCreateLock(lockURL.path)
      }
    }
  }

  private func discoverManifests(in root: URL) -> [URL] {
    guard
      let children = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    return children.compactMap { child in
      let candidate = child.appendingPathComponent("lunchpail.json")
      return FileManager.default.fileExists(atPath: candidate.path)
        ? canonicalManifestURL(candidate)
        : nil
    }
  }

  private func canonicalManifestURL(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath()
  }

  private func withRegistryLock<T>(_ operation: () throws -> T) throws -> T {
    let handle = try FileHandle(forUpdating: lockURL)
    defer { try? handle.close() }
    guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
      throw VMRegistryError.cannotLock(lockURL.path)
    }
    defer { flock(handle.fileDescriptor, LOCK_UN) }
    return try operation()
  }

  private func loadRegistry() throws -> RegistryFile {
    guard FileManager.default.fileExists(atPath: registryURL.path) else {
      return RegistryFile()
    }
    return try JSONDecoder().decode(RegistryFile.self, from: Data(contentsOf: registryURL))
  }

  private func writeRegistry(_ registry: RegistryFile) throws {
    let normalized = RegistryFile(
      manifestPaths: Array(Set(registry.manifestPaths)).sorted(),
      excludedManifestPaths: Array(Set(registry.excludedManifestPaths)).sorted()
    )
    try JSONEncoder.stable.encode(normalized).write(to: registryURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: registryURL.path
    )
  }

  private func hardenBundle(manifest: VMManifest, manifestURL: URL, directory: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let files = [
      manifestURL,
      try manifest.bundleURL(for: manifest.diskPath, baseURL: directory),
      try manifest.bundleURL(for: manifest.auxiliaryStoragePath, baseURL: directory),
    ]
    for file in files {
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
  }

  private static func identifier(for path: String) -> String {
    SHA256.hash(data: Data(path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
  }
}

private struct RegistryFile: Codable {
  var schemaVersion = 1
  var manifestPaths: [String]
  var excludedManifestPaths: [String]

  init(
    manifestPaths: [String] = [],
    excludedManifestPaths: [String] = []
  ) {
    self.manifestPaths = manifestPaths
    self.excludedManifestPaths = excludedManifestPaths
  }
}

public enum VMRegistryError: LocalizedError, Equatable {
  case notFound(String)
  case ambiguousSelector(String, [String])
  case cannotCreateLock(String)
  case cannotLock(String)

  public var errorDescription: String? {
    switch self {
    case .notFound(let selector):
      return "no registered VM matches \(selector)"
    case .ambiguousSelector(let selector, let identifiers):
      return
        "VM selector \(selector) is ambiguous; use one of: \(identifiers.joined(separator: ", "))"
    case .cannotCreateLock(let path):
      return "cannot create VM registry lock: \(path)"
    case .cannotLock(let path):
      return "cannot lock VM registry: \(path)"
    }
  }
}
