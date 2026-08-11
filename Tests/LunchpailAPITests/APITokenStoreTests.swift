import Foundation
import Testing

@testable import LunchpailAPI

@Test func apiTokenIsStableAndPrivate() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-api-token-\(UUID().uuidString)", isDirectory: true)
  let tokenURL = directory.appendingPathComponent("state/token")
  defer { try? FileManager.default.removeItem(at: directory) }

  let store = APITokenStore(tokenURL: tokenURL)
  let created = try store.loadOrCreate()
  let loaded = try store.loadOrCreate()
  let attributes = try FileManager.default.attributesOfItem(atPath: tokenURL.path)

  #expect(created.wasCreated)
  #expect(!loaded.wasCreated)
  #expect(created.value == loaded.value)
  #expect(created.value.utf8.count == 64)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func apiTokenRejectsShortExistingValue() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-api-token-\(UUID().uuidString)", isDirectory: true)
  let tokenURL = directory.appendingPathComponent("token")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data("short\n".utf8).write(to: tokenURL)
  defer { try? FileManager.default.removeItem(at: directory) }

  #expect(throws: APITokenError.invalidTokenFile(tokenURL.path)) {
    _ = try APITokenStore(tokenURL: tokenURL).loadOrCreate()
  }
}

@Test func apiTokenCreationIsConcurrencySafe() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lunchpail-api-token-\(UUID().uuidString)", isDirectory: true)
  let tokenURL = directory.appendingPathComponent("state/token")
  defer { try? FileManager.default.removeItem(at: directory) }

  let store = APITokenStore(tokenURL: tokenURL)
  let values = try await withThrowingTaskGroup(of: String.self) { group in
    for _ in 0..<32 {
      group.addTask { try store.loadOrCreate().value }
    }
    var values: [String] = []
    for try await value in group {
      values.append(value)
    }
    return values
  }

  #expect(Set(values).count == 1)
  #expect(values.first?.utf8.count == 64)
}
