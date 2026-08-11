import SwiftUI

struct SidebarView: View {
  @Binding var selection: AppSection?
  let activityMessage: String

  var body: some View {
    List(selection: $selection) {
      Section("Lunchpail") {
        ForEach(AppSection.allCases) { section in
          Label(section.title, systemImage: section.systemImage)
            .tag(section)
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 8) {
        Circle()
          .fill(.green)
          .frame(width: 7, height: 7)
        Text(activityMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)
    }
    .navigationTitle("Lunchpail")
  }
}
