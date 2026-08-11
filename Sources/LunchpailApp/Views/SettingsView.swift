import SwiftUI

struct SettingsView: View {
  @AppStorage("preferValidatedMetalProfiles") private var preferMetal = true
  @AppStorage("defaultHeadless") private var defaultHeadless = true
  @AppStorage("defaultVMCPUCount") private var defaultCPUCount = 8
  @AppStorage("defaultVMMemoryGiB") private var defaultMemoryGiB = 16

  var body: some View {
    TabView {
      Form {
        Toggle("Prefer validated Metal profiles", isOn: $preferMetal)
        Toggle("Create headless workers by default", isOn: $defaultHeadless)
        Text("Unknown platform or workload combinations always use stock Metal answers.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding()
      .tabItem { Label("General", systemImage: "gearshape") }

      Form {
        Stepper("Default CPUs: \(defaultCPUCount)", value: $defaultCPUCount, in: 1...64)
        Stepper(
          "Default memory: \(defaultMemoryGiB) GiB", value: $defaultMemoryGiB, in: 2...128, step: 2)
      }
      .padding()
      .tabItem { Label("Resources", systemImage: "cpu") }
    }
    .frame(width: 500, height: 270)
  }
}
