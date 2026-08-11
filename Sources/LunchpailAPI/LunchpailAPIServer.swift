import Foundation
import Hummingbird
import LunchpailCore

@MainActor
public struct LunchpailAPIServer: Sendable {
  public nonisolated static let version = "v1"

  public let hostname: String
  public let port: Int
  public let token: String
  public let registry: VMRegistry

  private let runtime: VMRuntimeService

  public init(
    hostname: String = "127.0.0.1",
    port: Int = 7777,
    token: String,
    registry: VMRegistry = VMRegistry(),
    runtime: VMRuntimeService = VMRuntimeService()
  ) {
    self.hostname = hostname
    self.port = port
    self.token = token
    self.registry = registry
    self.runtime = runtime
  }

  public func run() async throws {
    try Self.validateHostname(hostname)
    guard (1...65_535).contains(port) else {
      throw LunchpailAPIError.invalidPort(port)
    }

    let router = Router()
    router.middlewares.add(APIErrorMiddleware())
    router.get("/health") { _, _ in
      APIEnvelope(APIHealth(service: "lunchpail", version: Self.version, status: "ok"))
    }
    router.get("/openapi.yaml") { _, _ in
      EditedResponse(
        headers: [.contentType: "application/yaml; charset=utf-8"],
        response: try Self.openAPIDocument()
      )
    }
    router.middlewares.add(BearerTokenMiddleware(token: token))

    router.get("/v1/host") { _, _ in
      let report = try await Task.detached { try HostInspector().inspect() }.value
      return APIEnvelope(report)
    }
    router.get("/v1/metal/profiles") { _, _ in
      APIEnvelope(MetalProfileRegistry.all)
    }
    router.post("/v1/metal/probe") { request, context in
      let input = try await request.decode(as: APIMetalProbeRequest.self, context: context)
      let profile = try MetalProfileRegistry.profile(id: input.profile ?? "cua-m1-llamacpp")
      let artifacts = try MetalArtifactPaths.installedAdjacentToExecutable()
      return APIEnvelope(try MetalProbeRunner().compare(profile: profile, artifacts: artifacts))
    }
    router.post("/v1/metal/host/enable") { request, context in
      let input = try await request.decode(as: APIMetalHostEnableRequest.self, context: context)
      guard input.acknowledgePrivateAPIRisk else {
        throw HTTPError(
          .unprocessableContent, message: "private API risk acknowledgement is required")
      }
      return APIEnvelope(try HostMetalPreferenceManager().enable())
    }
    router.post("/v1/metal/host/restore") { _, _ in
      APIEnvelope(try HostMetalPreferenceManager().restore())
    }
    router.get("/v1/vms") { _, _ in
      let entries = try registry.list()
      let states = await runtime.statuses()
      return APIEnvelope(
        entries.map {
          APIVM(
            vm: $0,
            runtime: states[$0.id]
              ?? VMRuntimeStatus(vmID: $0.id, phase: .stopped, error: nil)
          )
        })
    }
    router.get("/v1/vms/:id") { _, context in
      guard let id = context.parameters.get("id") else { throw HTTPError(.badRequest) }
      let entry = try registry.resolve(String(id))
      return APIEnvelope(APIVM(vm: entry, runtime: await runtime.status(for: entry.id)))
    }
    router.post("/v1/vms/register") { request, context in
      let input = try await request.decode(as: APIRegisterVMRequest.self, context: context)
      return APIEnvelope(
        try registry.register(manifestURL: VMRegistry.manifestURL(from: input.manifestPath))
      )
    }
    router.post("/v1/vms/import-lume") { request, context in
      let input = try await request.decode(as: APIImportLumeRequest.self, context: context)
      let directory = URL(fileURLWithPath: NSString(string: input.directory).expandingTildeInPath)
        .standardizedFileURL
      let manifest = try LumeVMImporter().importManifest(
        from: directory,
        metalProfileID: input.profile ?? "stock"
      )
      let manifestURL = directory.appendingPathComponent("lunchpail.json")
      try manifest.write(to: manifestURL)
      return APIEnvelope(try registry.register(manifestURL: manifestURL))
    }
    router.post("/v1/vms/:id/clone") { request, context in
      guard let id = context.parameters.get("id") else { throw HTTPError(.badRequest) }
      let source = try registry.resolve(String(id))
      let input = try await request.decode(as: APICloneVMRequest.self, context: context)
      let destination = URL(
        fileURLWithPath: NSString(string: input.destination).expandingTildeInPath,
        isDirectory: true
      ).standardizedFileURL
      let report = try VMCloner().clone(
        sourceManifestURL: source.manifestURL,
        destinationDirectoryURL: destination,
        name: input.name ?? destination.lastPathComponent,
        allowFullCopy: input.allowFullCopy ?? false
      )
      _ = try registry.register(
        manifestURL: URL(fileURLWithPath: report.destinationManifestPath)
      )
      return APIEnvelope(report)
    }
    router.post("/v1/vms/:id/start") { _, context in
      guard let id = context.parameters.get("id") else { throw HTTPError(.badRequest) }
      let entry = try registry.resolve(String(id))
      return EditedResponse(
        status: .accepted, response: APIEnvelope(try await runtime.start(entry)))
    }
    router.post("/v1/vms/:id/stop") { request, context in
      guard let id = context.parameters.get("id") else { throw HTTPError(.badRequest) }
      let entry = try registry.resolve(String(id))
      let force = request.uri.queryParameters.get("force", as: Bool.self) ?? false
      return EditedResponse(
        status: .accepted,
        response: APIEnvelope(try await runtime.stop(vmID: entry.id, force: force))
      )
    }

    let app = Application(
      responder: router.buildResponder(),
      configuration: .init(
        address: .hostname(hostname, port: port),
        serverName: "lunchpail-api"
      )
    )
    do {
      try await app.runService()
    } catch {
      await runtime.shutdown()
      throw error
    }
    await runtime.shutdown()
  }

  public nonisolated static func validateHostname(_ hostname: String) throws {
    guard hostname == "127.0.0.1" || hostname == "::1" else {
      throw LunchpailAPIError.nonLoopbackAddress(hostname)
    }
  }

  nonisolated private static func openAPIDocument() throws -> String {
    guard let url = Bundle.module.url(forResource: "openapi", withExtension: "yaml") else {
      throw LunchpailAPIError.missingOpenAPIDocument
    }
    return try String(contentsOf: url, encoding: .utf8)
  }
}

public enum LunchpailAPIError: LocalizedError, Equatable {
  case nonLoopbackAddress(String)
  case invalidPort(Int)
  case missingOpenAPIDocument

  public var errorDescription: String? {
    switch self {
    case .nonLoopbackAddress(let address):
      return "refusing non-loopback API address without TLS: \(address)"
    case .invalidPort(let port): return "invalid API port: \(port)"
    case .missingOpenAPIDocument: return "bundled OpenAPI document is missing"
    }
  }
}
