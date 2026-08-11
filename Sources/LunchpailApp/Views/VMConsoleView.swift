import SwiftUI
import Virtualization

struct VMConsoleView: View {
  let model: LunchpailAppModel
  @State private var capturesSystemKeys = false
  @State private var confirmingForceStop = false

  var body: some View {
    Group {
      if let virtualMachine = model.consoleVirtualMachine {
        VirtualMachineDisplay(
          virtualMachine: virtualMachine,
          capturesSystemKeys: capturesSystemKeys
        )
        .background(.black)
      } else {
        ContentUnavailableView(
          "No Running VM",
          systemImage: "macwindow",
          description: Text("Start a virtual machine from the Virtual Machines screen.")
        )
      }
    }
    .navigationTitle(consoleTitle)
    .toolbar {
      ToolbarItemGroup {
        Toggle(isOn: $capturesSystemKeys) {
          Label("Capture System Keys", systemImage: "keyboard")
        }
        .disabled(model.consoleVirtualMachine == nil)

        Menu("Power") {
          Button("Shut Down Gracefully") { model.requestStop() }
          Divider()
          Button("Force Stop", role: .destructive) {
            confirmingForceStop = true
          }
        }
        .disabled(model.consoleVirtualMachine == nil)
      }
    }
    .alert("Force stop the virtual machine?", isPresented: $confirmingForceStop) {
      Button("Cancel", role: .cancel) {}
      Button("Force Stop", role: .destructive) { model.forceStop() }
    } message: {
      Text("The guest will not have a chance to flush filesystems or shut down cleanly.")
    }
  }

  private var consoleTitle: String {
    guard let manifestURL = model.runningManifestURL else { return "VM Console" }
    return "\(manifestURL.deletingLastPathComponent().lastPathComponent) — VM Console"
  }
}

private struct VirtualMachineDisplay: NSViewRepresentable {
  let virtualMachine: VZVirtualMachine
  let capturesSystemKeys: Bool

  func makeNSView(context: Context) -> VZVirtualMachineView {
    let view = VZVirtualMachineView()
    view.virtualMachine = virtualMachine
    view.capturesSystemKeys = capturesSystemKeys
    view.automaticallyReconfiguresDisplay = true
    return view
  }

  func updateNSView(_ view: VZVirtualMachineView, context: Context) {
    if view.virtualMachine !== virtualMachine {
      view.virtualMachine = virtualMachine
    }
    if view.capturesSystemKeys != capturesSystemKeys {
      view.capturesSystemKeys = capturesSystemKeys
    }
  }

  static func dismantleNSView(_ view: VZVirtualMachineView, coordinator: ()) {
    view.automaticallyReconfiguresDisplay = false
    view.virtualMachine = nil
  }
}
