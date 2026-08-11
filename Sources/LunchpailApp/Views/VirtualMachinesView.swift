import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VirtualMachinesView: View {
  let model: LunchpailAppModel
  @Environment(\.openWindow) private var openWindow
  @State private var showingImporter = false
  @State private var showingCreator = false
  @State private var cloneSource: VMRecord?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Virtual Machines")
              .font(.largeTitle.weight(.semibold))
            Text("One manifest format and runtime for the native app and CLI.")
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            showingCreator = true
          } label: {
            Label("Create VM", systemImage: "plus.rectangle.on.rectangle")
          }
          .keyboardShortcut("n")
          Button {
            showingImporter = true
          } label: {
            Label("Import", systemImage: "square.and.arrow.down")
          }
          .keyboardShortcut("o")
        }

        if model.machines.isEmpty {
          ContentUnavailableView(
            "No VMs Yet",
            systemImage: "shippingbox",
            description: Text("Create a macOS VM from an IPSW or import a Lunchpail manifest.")
          )
          .frame(maxWidth: .infinity, minHeight: 320)
        } else {
          LazyVStack(spacing: 12) {
            ForEach(model.machines) { machine in
              MachineRow(
                model: model,
                machine: machine,
                onRun: {
                  if model.start(machine) {
                    openWindow(id: "vm-console")
                  }
                },
                onClone: { cloneSource = machine }
              )
            }
          }
        }
      }
      .padding(24)
    }
    .navigationTitle("Virtual Machines")
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first { model.importManifest(url) }
      case .failure(let error):
        model.errorMessage = error.localizedDescription
      }
    }
    .sheet(item: $cloneSource) { machine in
      CloneVMSheet(model: model, machine: machine)
    }
    .sheet(isPresented: $showingCreator) {
      CreateMacVMView(model: model)
    }
  }
}

private struct MachineRow: View {
  let model: LunchpailAppModel
  let machine: VMRecord
  let onRun: () -> Void
  let onClone: () -> Void
  @State private var confirmingForceStop = false

  private var isRunning: Bool {
    model.runningManifestURL == machine.manifestURL
  }

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: isRunning ? "play.square.stack.fill" : "macwindow.on.rectangle")
        .font(.title)
        .foregroundStyle(isRunning ? .green : .secondary)
        .frame(width: 40)

      VStack(alignment: .leading, spacing: 5) {
        Text(machine.name)
          .font(.headline)
        Text(
          "\(machine.cpuCount) vCPU · \(LunchpailFormatters.bytes(machine.memoryBytes)) · \(machine.metalProfileID)"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        Text(machine.manifestURL.path)
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }

      Spacer()

      Text(machine.validationDescription)
        .font(.caption)
        .foregroundStyle(machine.validationState == .ready ? .green : .red)

      if isRunning {
        Menu("Stop") {
          Button("Shut Down Gracefully") { model.requestStop() }
          Divider()
          Button("Force Stop", role: .destructive) {
            confirmingForceStop = true
          }
        }
      } else {
        Button("Run", action: onRun)
          .disabled(machine.validationState != .ready || model.runningManifestURL != nil)
          .buttonStyle(.borderedProminent)
      }

      Menu {
        Button("Clone…", action: onClone)
          .disabled(isRunning || machine.validationState != .ready || model.isCloning)
        Button("Reveal Manifest in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([machine.manifestURL])
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .alert("Force stop \(machine.name)?", isPresented: $confirmingForceStop) {
      Button("Cancel", role: .cancel) {}
      Button("Force Stop", role: .destructive) { model.forceStop() }
    } message: {
      Text("The guest will not have a chance to flush filesystems or shut down cleanly.")
    }
  }
}

private struct CloneVMSheet: View {
  let model: LunchpailAppModel
  let machine: VMRecord
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var parentDirectory: URL
  @State private var choosingDirectory = false

  init(model: LunchpailAppModel, machine: VMRecord) {
    self.model = model
    self.machine = machine
    _name = State(initialValue: "\(machine.name)-copy")
    _parentDirectory = State(
      initialValue: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
          "Library/Application Support/Lunchpail/VMs",
          isDirectory: true
        )
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Clone \(machine.name)")
        .font(.title2.weight(.semibold))

      Form {
        TextField("Name", text: $name)
        LabeledContent("Destination") {
          HStack {
            Text(parentDirectory.path)
              .lineLimit(1)
              .truncationMode(.middle)
            Button("Choose…") { choosingDirectory = true }
          }
        }
      }

      Text(
        "Lunchpail requires an APFS copy-on-write clone and creates a new machine identifier and MAC address. The source must be stopped."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Clone") {
          model.clone(machine, name: name, parentDirectory: parentDirectory)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(name.isEmpty || model.isCloning)
      }
    }
    .padding(22)
    .frame(width: 580)
    .fileImporter(
      isPresented: $choosingDirectory,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first { parentDirectory = url }
      case .failure(let error):
        model.errorMessage = error.localizedDescription
      }
    }
  }
}
