import SwiftUI

struct ContentView: View {
  @Bindable var model: LunchpailAppModel

  var body: some View {
    NavigationSplitView {
      SidebarView(selection: $model.selection, activityMessage: model.activityMessage)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    } detail: {
      Group {
        switch model.selection ?? .overview {
        case .overview:
          OverviewView(model: model)
        case .virtualMachines:
          VirtualMachinesView(model: model)
        case .metal:
          MetalProfilesView(model: model)
        case .benchmarks:
          BenchmarksView()
        }
      }
      .toolbar {
        ToolbarItemGroup {
          Button {
            model.refresh()
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(model.isRefreshing)

          SettingsLink {
            Label("Settings", systemImage: "gearshape")
          }
        }
      }
    }
    .alert(
      "Lunchpail",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "Unknown error")
    }
  }
}
