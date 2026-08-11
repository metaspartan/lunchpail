import SwiftUI

struct StatusCard: View {
  let title: String
  let value: String
  let detail: String
  let systemImage: String
  var tint: Color = .accentColor

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
          .font(.title2)
        Spacer()
      }
      Text(value)
        .font(.title2.weight(.semibold))
        .lineLimit(1)
      Text(title)
        .font(.headline)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
  }
}
