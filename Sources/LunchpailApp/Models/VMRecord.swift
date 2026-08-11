import Foundation
import LunchpailCore

enum VMValidationState: Sendable, Equatable {
  case ready
  case invalid(String)
}

struct VMRecord: Identifiable, Sendable, Equatable {
  let manifestURL: URL
  let name: String
  let cpuCount: Int
  let memoryBytes: UInt64
  let metalProfileID: String
  let validationState: VMValidationState

  var id: URL { manifestURL }

  var validationDescription: String {
    switch validationState {
    case .ready: "Ready"
    case .invalid(let message): message
    }
  }
}
