import Foundation

enum AppSection: String, CaseIterable, Identifiable {
  case overview
  case virtualMachines
  case metal
  case benchmarks

  var id: Self { self }

  var title: String {
    switch self {
    case .overview: "Overview"
    case .virtualMachines: "Virtual Machines"
    case .metal: "Metal"
    case .benchmarks: "Benchmarks"
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "gauge.with.dots.needle.67percent"
    case .virtualMachines: "shippingbox"
    case .metal: "sparkles.rectangle.stack"
    case .benchmarks: "chart.xyaxis.line"
    }
  }
}
