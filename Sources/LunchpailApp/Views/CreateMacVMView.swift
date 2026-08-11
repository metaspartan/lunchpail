import LunchpailCore
import SwiftUI
import UniformTypeIdentifiers

struct CreateMacVMView: View {
  let model: LunchpailAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var name = "macos-worker"
  @State private var restoreImageURL: URL?
  @State private var parentDirectory = VMRegistry().vmDirectoryURL
  @State private var cpuCount = min(ProcessInfo.processInfo.processorCount, 8)
  @State private var memoryGiB = 8
  @State private var diskGiB = 80
  @State private var profile = MetalProfileRegistry.stock.id
  @State private var choosingRestoreImage = false
  @State private var choosingDirectory = false
  @State private var didStart = false

  private var restoreImageType: UTType {
    UTType(filenameExtension: "ipsw") ?? .data
  }

  private var canInstall: Bool {
    VMManifest.isValidName(name)
      && restoreImageURL != nil
      && !model.isInstalling
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Create macOS VM")
          .font(.title2.weight(.semibold))
        Text("Install a supported Apple silicon restore image into an atomic sparse VM.")
          .foregroundStyle(.secondary)
      }

      Form {
        TextField("Name", text: $name)
        LabeledContent("Restore image") {
          HStack {
            Text(restoreImageURL?.lastPathComponent ?? "Choose an IPSW")
              .foregroundStyle(restoreImageURL == nil ? .secondary : .primary)
              .lineLimit(1)
            Button("Choose…") { choosingRestoreImage = true }
          }
        }
        LabeledContent("Destination") {
          HStack {
            Text(parentDirectory.appendingPathComponent(name).path)
              .lineLimit(1)
              .truncationMode(.middle)
            Button("Choose…") { choosingDirectory = true }
          }
        }
        Stepper("Virtual CPUs: \(cpuCount)", value: $cpuCount, in: 1...64)
        Stepper("Memory: \(memoryGiB) GiB", value: $memoryGiB, in: 4...256, step: 4)
        Stepper("Disk: \(diskGiB) GiB", value: $diskGiB, in: 64...1_024, step: 16)
        Picker("Metal profile", selection: $profile) {
          ForEach(MetalProfileRegistry.all, id: \.id) { profile in
            Text(profile.id).tag(profile.id)
          }
        }
      }

      if model.isInstalling {
        VStack(alignment: .leading, spacing: 6) {
          ProgressView(value: model.installationProgress)
          Text("Installing macOS · \(Int(model.installationProgress * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(model.isInstalling)
        Button("Create") {
          guard let restoreImageURL else { return }
          didStart = true
          model.installMacOS(
            name: name,
            restoreImageURL: restoreImageURL,
            parentDirectory: parentDirectory,
            cpuCount: cpuCount,
            memoryGiB: memoryGiB,
            diskGiB: diskGiB,
            profile: profile
          )
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!canInstall)
      }
    }
    .padding(22)
    .frame(width: 620)
    .fileImporter(
      isPresented: $choosingRestoreImage,
      allowedContentTypes: [restoreImageType],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        restoreImageURL = urls.first
      case .failure(let error):
        model.errorMessage = error.localizedDescription
      }
    }
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
    .onChange(of: model.isInstalling) { _, isInstalling in
      if didStart && !isInstalling && model.errorMessage == nil {
        dismiss()
      }
    }
  }
}
