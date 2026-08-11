import Foundation

public struct LunchpailAPIClient: Sendable {
  public let baseURL: URL
  public let token: String

  public init(baseURL: URL, token: String) {
    self.baseURL = baseURL
    self.token = token
  }

  public func health() async throws -> APIHealth {
    try await get("/health", authenticated: false, as: APIEnvelope<APIHealth>.self).data
  }

  public func vm(vmID: String) async throws -> APIVM {
    try await get("/v1/vms/\(vmID)", as: APIEnvelope<APIVM>.self).data
  }

  public func start(vmID: String) async throws -> VMRuntimeStatus {
    try await post("/v1/vms/\(vmID)/start", as: APIEnvelope<VMRuntimeStatus>.self).data
  }

  public func stop(vmID: String, force: Bool) async throws -> VMRuntimeStatus {
    let suffix = force ? "?force=true" : ""
    return try await post(
      "/v1/vms/\(vmID)/stop\(suffix)",
      as: APIEnvelope<VMRuntimeStatus>.self
    ).data
  }

  private func get<Value: Decodable>(
    _ path: String,
    authenticated: Bool = true,
    as type: Value.Type
  ) async throws -> Value {
    try await request(path, method: "GET", authenticated: authenticated, as: type)
  }

  private func post<Value: Decodable>(
    _ path: String,
    as type: Value.Type
  ) async throws -> Value {
    try await request(path, method: "POST", authenticated: true, as: type)
  }

  private func request<Value: Decodable>(
    _ path: String,
    method: String,
    authenticated: Bool,
    as type: Value.Type
  ) async throws -> Value {
    guard let url = URL(string: path, relativeTo: baseURL) else {
      throw LunchpailAPIClientError.invalidURL(path)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 10
    if authenticated {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw LunchpailAPIClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      throw LunchpailAPIClientError.httpFailure(
        http.statusCode,
        String(decoding: data, as: UTF8.self)
      )
    }
    return try JSONDecoder().decode(type, from: data)
  }
}

public enum LunchpailAPIClientError: LocalizedError, Equatable {
  case invalidURL(String)
  case invalidResponse
  case httpFailure(Int, String)

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let path): return "invalid API path: \(path)"
    case .invalidResponse: return "Lunchpail API returned a non-HTTP response"
    case .httpFailure(let status, let body):
      return "Lunchpail API returned HTTP \(status): \(body)"
    }
  }
}
