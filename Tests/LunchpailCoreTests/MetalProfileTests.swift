import Foundation
import Testing

@testable import LunchpailCore

@Test func researchProfileIsNarrow() throws {
  let profile = MetalProfileRegistry.cuaM1LlamaCPP
  let environment = try profile.environment(
    shimURL: URL(fileURLWithPath: "/guest/libLunchpailMetalShim.dylib")
  )

  #expect(environment["LUNCHPAIL_METAL_APPLE_FAMILY_MAX"] == "1009")
  #expect(environment["LUNCHPAIL_METAL_MAX_THREADGROUP_MEMORY"] == "65536")
  #expect(environment["DYLD_INSERT_LIBRARIES"] == "/guest/libLunchpailMetalShim.dylib")
  #expect(environment["LUNCHPAIL_METAL_RECOMMENDED_WORKING_SET_SIZE"] == nil)
  #expect(environment.keys.allSatisfy { !$0.contains("METAL3") })
}

@Test func stockProfileHasNoInjectedEnvironment() throws {
  let environment = try MetalProfileRegistry.stock.environment(
    shimURL: URL(fileURLWithPath: "/unused")
  )
  #expect(environment.isEmpty)
}

@Test func probeOutputParsing() throws {
  let result = try MetalProbeResult(
    output: """
      device=Apple M1 Ultra
      family=1009
      supports_family=true
      max_threadgroup_memory=65536
      recommended_working_set=1073741824
      supports_metal3=false
      extra_key=is ignored
      """)
  #expect(result.device == "Apple M1 Ultra")
  #expect(result.family == 1009)
  #expect(result.supportsFamily)
  #expect(result.maxThreadgroupMemoryBytes == 65_536)
  #expect(result.recommendedWorkingSetBytes == 1_073_741_824)
  #expect(!result.supportsMetal3)
}

@Test func expectedProbeComparisonRejectsDeviceChanges() throws {
  let stock = try MetalProbeResult(
    output: """
      device=Apple M1 Ultra
      family=1009
      supports_family=false
      max_threadgroup_memory=32768
      recommended_working_set=1073741824
      supports_metal3=false
      """)
  let profiled = try MetalProbeResult(
    output: """
      device=Different device
      family=1009
      supports_family=true
      max_threadgroup_memory=65536
      recommended_working_set=1073741824
      supports_metal3=false
      """)
  let comparison = MetalProbeComparison(
    profileID: "test",
    stock: stock,
    profiled: profiled
  )
  #expect(!comparison.changedOnlyExpectedCapabilities)
}

@Test func expectedProbeComparisonRejectsBroaderMetalFamilyChanges() throws {
  let stock = try MetalProbeResult(
    output: """
      device=Apple Paravirtual device
      family=1009
      supports_family=false
      max_threadgroup_memory=32768
      recommended_working_set=1073741824
      supports_metal3=false
      """)
  let profiled = try MetalProbeResult(
    output: """
      device=Apple Paravirtual device
      family=1009
      supports_family=true
      max_threadgroup_memory=65536
      recommended_working_set=1073741824
      supports_metal3=true
      """)
  let comparison = MetalProbeComparison(
    profileID: "test",
    stock: stock,
    profiled: profiled
  )
  #expect(!comparison.changedOnlyExpectedCapabilities)
}
