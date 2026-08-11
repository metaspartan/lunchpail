import SwiftUI

struct BenchmarksView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Benchmarks")
            .font(.largeTitle.weight(.semibold))
          Text(
            "Latest automated certification on this M1 Ultra, using the same guest, binary, model, and arguments."
          )
          .foregroundStyle(.secondary)
        }

        HStack(spacing: 14) {
          BenchmarkCard(
            title: "Prompt processing",
            stock: "413.33 tok/s",
            profiled: "5,112.16 tok/s",
            speedup: "12.37×"
          )
          BenchmarkCard(
            title: "Token generation",
            stock: "9.21 tok/s",
            profiled: "167.17 tok/s",
            speedup: "18.16×"
          )
        }

        GroupBox("Canary identity") {
          Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
            CanaryRow(label: "Guest", value: "macOS 26.5.2 · 8 vCPU · 64 GiB")
            CanaryRow(label: "Runtime", value: "llama.cpp b10359 · commit 84f712946")
            CanaryRow(label: "Model", value: "TinyLlama 1.1B Q4_K_M")
            CanaryRow(label: "Profile", value: "Apple family 9 · 64 KiB threadgroup")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        }

        GroupBox("Certification") {
          VStack(alignment: .leading, spacing: 8) {
            Label(
              "Passed capability, artifact, identity, and speedup checks",
              systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
            Text(
              "The JSON record contains all samples and SHA-256 hashes and can be regenerated with `lunchpail metal benchmark llama`."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        }

        Text(
          "Performance is a release gate, not a slogan. Future CI records cold boot, warm boot, clone time, disk and network throughput, memory overhead, and representative AI throughput against Lume, Tart, and Apple container where the workloads are comparable."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      .padding(24)
    }
    .navigationTitle("Benchmarks")
  }
}

private struct BenchmarkCard: View {
  let title: String
  let stock: String
  let profiled: String
  let speedup: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        Text(speedup)
          .font(.title2.weight(.bold))
          .foregroundStyle(.green)
      }
      LabeledContent("Stock", value: stock)
      LabeledContent("Profiled", value: profiled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
  }
}

private struct CanaryRow: View {
  let label: String
  let value: String

  var body: some View {
    GridRow {
      Text(label)
        .foregroundStyle(.secondary)
      Text(value)
        .textSelection(.enabled)
    }
  }
}
