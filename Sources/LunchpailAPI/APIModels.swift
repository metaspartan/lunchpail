import Hummingbird
import LunchpailCore

public struct APIEnvelope<Value: Codable & Sendable>: ResponseCodable, Sendable {
  public let data: Value

  public init(_ data: Value) {
    self.data = data
  }
}

public struct APIHealth: Codable, Sendable {
  public let service: String
  public let version: String
  public let status: String
}

public struct APIVM: Codable, Sendable {
  public let vm: VMInventoryEntry
  public let runtime: VMRuntimeStatus
}

public struct APIRegisterVMRequest: Codable, Sendable {
  public let manifestPath: String
}

public struct APIImportLumeRequest: Codable, Sendable {
  public let directory: String
  public let profile: String?
}

public struct APICloneVMRequest: Codable, Sendable {
  public let destination: String
  public let name: String?
  public let allowFullCopy: Bool?
}

public struct APIMetalHostEnableRequest: Codable, Sendable {
  public let acknowledgePrivateAPIRisk: Bool
}

public struct APIMetalProbeRequest: Codable, Sendable {
  public let profile: String?
}
