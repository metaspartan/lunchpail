import ArgumentParser
import Foundation
import LunchpailAPI

struct API: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Run and inspect the local HTTP API for agents and automation.",
    subcommands: [APIServe.self, APIStatus.self, APIToken.self]
  )
}

struct APIServe: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "serve",
    abstract: "Serve the authenticated API on the loopback interface."
  )

  @Option(help: "Numeric loopback address: 127.0.0.1 or ::1.")
  var host = "127.0.0.1"

  @Option(help: "TCP port.")
  var port = 7777

  @MainActor
  mutating func run() async throws {
    let token = try APITokenStore().loadOrCreate()
    print("Lunchpail API: http://\(host):\(port)")
    print("OpenAPI: http://\(host):\(port)/openapi.yaml")
    print("token file: \(token.url.path)")
    try await LunchpailAPIServer(hostname: host, port: port, token: token.value).run()
  }
}

struct APIStatus: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Check the local API service."
  )

  @Option(help: "Local API port.")
  var port = 7777

  @Flag(help: "Emit machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let health = try await LunchpailCLIAPI.client(port: port).health()
    if json {
      try Output.json(health)
    } else {
      print("\(health.service) API \(health.version): \(health.status)")
    }
  }
}

struct APIToken: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "token",
    abstract: "Create or inspect the local API token."
  )

  @Flag(help: "Print the token value for local client configuration.")
  var show = false

  mutating func run() throws {
    let record = try APITokenStore().loadOrCreate()
    if show {
      print(record.value)
    } else {
      print(record.url.path)
    }
  }
}

enum LunchpailCLIAPI {
  static func client(port: Int) throws -> LunchpailAPIClient {
    let token = try APITokenStore().loadOrCreate().value
    guard let url = URL(string: "http://127.0.0.1:\(port)") else {
      throw ValidationError("invalid API port")
    }
    return LunchpailAPIClient(baseURL: url, token: token)
  }
}
