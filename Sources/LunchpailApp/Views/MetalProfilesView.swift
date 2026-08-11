import LunchpailCore
import SwiftUI

struct MetalProfilesView: View {
  let model: LunchpailAppModel
  @State private var showingRiskConfirmation = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Metal")
              .font(.largeTitle.weight(.semibold))
            Text("Versioned capability contracts, scoped to one guest process.")
              .foregroundStyle(.secondary)
          }
          Spacer()
          bridgeAction
        }

        HStack(spacing: 10) {
          Image(
            systemName: model.metalIsReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(model.metalIsReady ? .green : .orange)
          Text(
            model.metalIsReady
              ? "The host bridge is ready for VMs launched by this user."
              : "The private host bridge is off; stock Metal remains available.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

        ForEach(MetalProfileRegistry.all, id: \.id) { profile in
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(profile.id)
                  .font(.headline.monospaced())
                Text(profile.summary)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(profile.maturity.rawValue.capitalized)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }

            if let family = profile.appleFamilyMaximum {
              Divider()
              LabeledContent("Apple family maximum", value: String(family))
              LabeledContent(
                "Threadgroup memory",
                value: LunchpailFormatters.bytes(UInt64(profile.maxThreadgroupMemoryBytes ?? 0))
              )
              LabeledContent(
                "Validated workloads", value: profile.validatedWorkloads.joined(separator: ", "))
            }
          }
          .padding(16)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }

        Text(
          "Research profiles are never a blanket promise. Lunchpail must rerun compatibility and performance canaries after host, guest, compiler, or workload changes."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      .padding(24)
    }
    .navigationTitle("Metal")
    .alert("Enable experimental Metal bridge?", isPresented: $showingRiskConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Enable") { model.enableMetal() }
    } message: {
      Text(
        "This journals and changes an undocumented per-user Apple preference. Stop other macOS VMs first and use only trusted guests."
      )
    }
  }

  @ViewBuilder
  private var bridgeAction: some View {
    if model.hostReport?.preferenceBackupPending == true {
      Button("Restore Previous Setting") { model.restoreMetalPreference() }
    } else if !model.metalIsReady {
      Button("Enable Metal Bridge") { showingRiskConfirmation = true }
        .buttonStyle(.borderedProminent)
    }
  }
}
