import Foundation
import Testing

@testable import LunchpailAPI

@Test func serverAcceptsOnlyNumericLoopbackAddresses() throws {
  try LunchpailAPIServer.validateHostname("127.0.0.1")
  try LunchpailAPIServer.validateHostname("::1")
  #expect(throws: LunchpailAPIError.nonLoopbackAddress("localhost")) {
    try LunchpailAPIServer.validateHostname("localhost")
  }
  #expect(throws: LunchpailAPIError.nonLoopbackAddress("0.0.0.0")) {
    try LunchpailAPIServer.validateHostname("0.0.0.0")
  }
}

@Test func metalProbeRequestIgnoresArtifactPathFields() throws {
  let data = Data(
    #"{"profile":"cua-m1-llamacpp","probePath":"/tmp/payload","shimPath":"/tmp/payload.dylib"}"#
      .utf8
  )
  let request = try JSONDecoder().decode(APIMetalProbeRequest.self, from: data)
  let encoded = try JSONEncoder().encode(request)
  let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  #expect(object["profile"] as? String == "cua-m1-llamacpp")
  #expect(object["probePath"] == nil)
  #expect(object["shimPath"] == nil)
}
