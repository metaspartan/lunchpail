import LunchpailCore
import SwiftUI

struct OverviewView: View {
  let model: LunchpailAppModel

  private let columns = [
    GridItem(.adaptive(minimum: 210), spacing: 14)
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Apple silicon VMs, with the GPU awake.")
            .font(.largeTitle.weight(.semibold))
          Text(
            "A native runtime for fast macOS and Linux workers, with measured Metal profiles for macOS AI workloads."
          )
          .font(.title3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        LazyVGrid(columns: columns, spacing: 14) {
          StatusCard(
            title: "Host",
            value: model.hostReport?.chip ?? "Inspecting…",
            detail: hostDetail,
            systemImage: "cpu",
            tint: .blue
          )
          StatusCard(
            title: "Metal bridge",
            value: model.metalIsReady ? "Ready" : "Setup needed",
            detail: model.metalIsReady
              ? "New macOS VMs can launch validated profiled workloads."
              : "Enable once, then Lunchpail can select validated profiles by default.",
            systemImage: "sparkles.rectangle.stack",
            tint: model.metalIsReady ? .green : .orange
          )
          StatusCard(
            title: "Virtual machines",
            value: String(model.machines.count),
            detail: "Imported manifests discovered on this Mac.",
            systemImage: "shippingbox",
            tint: .purple
          )
          StatusCard(
            title: "TinyLlama canary",
            value: "12.91× / 20.75×",
            detail: "Prompt / generation speedup measured in the Tahoe guest on this M1 Ultra.",
            systemImage: "bolt.fill",
            tint: .yellow
          )
        }

        GroupBox("Product contract") {
          VStack(alignment: .leading, spacing: 10) {
            ContractRow(
              text:
                "Metal defaults on only for a host, guest, and workload combination that passed its canary."
            )
            ContractRow(text: "Unknown combinations fall back to Apple's stock capability answers.")
            ContractRow(
              text:
                "The GUI and CLI share the same manifests, validation, preference journal, and VM runner."
            )
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        }
      }
      .padding(24)
    }
    .navigationTitle("Overview")
  }

  private var hostDetail: String {
    guard let host = model.hostReport else {
      return "Reading Metal and Virtualization capabilities."
    }
    return
      "\(host.logicalCPUCount) CPUs · \(LunchpailFormatters.bytes(host.physicalMemoryBytes)) · macOS build \(host.osBuild)"
  }
}

private struct ContractRow: View {
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text(text)
    }
  }
}
