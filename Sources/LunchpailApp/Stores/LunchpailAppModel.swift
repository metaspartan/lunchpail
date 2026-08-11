import Foundation
import LunchpailCore
import Observation
import Virtualization

@MainActor
@Observable
final class LunchpailAppModel {
  var selection: AppSection? = .overview
  var hostReport: HostReport?
  var machines: [VMRecord] = []
  var isRefreshing = false
  var errorMessage: String?
  var runningManifestURL: URL?
  var consoleVirtualMachine: VZVirtualMachine?
  var activityMessage = "Ready"
  var isCloning = false
  var isInstalling = false
  var installationProgress = 0.0

  @ObservationIgnored private let discovery = VMDiscoveryService()
  @ObservationIgnored private var runner: MacVMRunner?
  @ObservationIgnored private var lifecycleLock: VMDirectoryLock?
  @ObservationIgnored private var runTask: Task<Void, Never>?

  var metalIsReady: Bool {
    hostReport?.unrestrictedGraphicsPreference.enabled == true
  }

  var canRunVM: Bool {
    hostReport?.virtualizationSupported == true
      && hostReport?.virtualizationEntitlementPresent == true
  }

  func refresh() {
    guard !isRefreshing else { return }
    isRefreshing = true
    errorMessage = nil
    Task {
      defer { isRefreshing = false }
      do {
        let report = try await Task.detached {
          try HostInspector().inspect()
        }.value
        hostReport = report
        machines = discovery.discover()
        activityMessage = "Checked host and \(machines.count) VM\(machines.count == 1 ? "" : "s")"
      } catch {
        errorMessage = error.localizedDescription
        activityMessage = "Refresh failed"
      }
    }
  }

  func importManifest(_ url: URL) {
    discovery.remember(url)
    machines = discovery.discover()
    selection = .virtualMachines
    activityMessage = "Imported \(url.lastPathComponent)"
  }

  func clone(_ machine: VMRecord, name: String, parentDirectory: URL) {
    guard !isCloning else {
      errorMessage = "Another clone is already in progress."
      return
    }
    isCloning = true
    activityMessage = "Cloning \(machine.name)"
    let destination = parentDirectory.appendingPathComponent(name, isDirectory: true)
    Task {
      defer { isCloning = false }
      do {
        let report = try await Task.detached(priority: .userInitiated) {
          try VMCloner().clone(
            sourceManifestURL: machine.manifestURL,
            destinationDirectoryURL: destination,
            name: name
          )
        }.value
        let manifestURL = URL(fileURLWithPath: report.destinationManifestPath)
        discovery.remember(manifestURL)
        machines = discovery.discover()
        activityMessage = String(
          format: "Cloned %@ in %.3f seconds",
          machine.name,
          report.elapsedSeconds
        )
      } catch {
        errorMessage = error.localizedDescription
        activityMessage = "Clone failed"
      }
    }
  }

  func installMacOS(
    name: String,
    restoreImageURL: URL,
    parentDirectory: URL,
    cpuCount: Int,
    memoryGiB: Int,
    diskGiB: Int,
    profile: String
  ) {
    guard !isInstalling else {
      errorMessage = "Another macOS installation is already in progress."
      return
    }
    guard canRunVM else {
      errorMessage = "Virtualization is unavailable or the app is not signed with its entitlement."
      return
    }
    isInstalling = true
    installationProgress = 0
    errorMessage = nil
    activityMessage = "Preparing \(name)"
    let destination = parentDirectory.appendingPathComponent(name, isDirectory: true)
    let gibibyte = UInt64(1_024 * 1_024 * 1_024)
    Task {
      defer { isInstalling = false }
      do {
        let report = try await MacVMInstaller().install(
          MacVMInstallRequest(
            name: name,
            destinationDirectoryURL: destination,
            restoreImageURL: restoreImageURL,
            cpuCount: cpuCount,
            memoryBytes: UInt64(memoryGiB) * gibibyte,
            diskBytes: UInt64(diskGiB) * gibibyte,
            metalProfileID: profile
          )
        ) { [weak self] fraction in
          Task { @MainActor [weak self] in
            self?.installationProgress = fraction
            self?.activityMessage = "Installing \(name): \(Int(fraction * 100))%"
          }
        }
        let manifestURL = URL(fileURLWithPath: report.manifestPath)
        discovery.remember(manifestURL)
        machines = discovery.discover()
        installationProgress = 1
        activityMessage = "Installed \(name)"
      } catch {
        errorMessage = error.localizedDescription
        activityMessage = "Installation failed"
      }
    }
  }

  @discardableResult
  func start(_ machine: VMRecord) -> Bool {
    guard runner == nil else {
      errorMessage = "Another virtual machine is already running in this app."
      return false
    }
    guard machine.validationState == .ready else {
      errorMessage = machine.validationDescription
      return false
    }
    guard canRunVM else {
      errorMessage = "Virtualization is unavailable or the app is not signed with its entitlement."
      return false
    }
    if machine.metalProfileID != MetalProfileRegistry.stock.id && !metalIsReady {
      errorMessage = "Enable the host Metal bridge before starting this profiled VM."
      selection = .metal
      return false
    }

    do {
      let newLock = try VMDirectoryLock(
        directoryURL: machine.manifestURL.deletingLastPathComponent(),
        mode: .exclusive
      )
      let configuration = try MacVMConfigurationBuilder.build(
        manifestURL: machine.manifestURL
      )
      let newRunner = MacVMRunner(configuration: configuration)
      lifecycleLock = newLock
      runner = newRunner
      consoleVirtualMachine = newRunner.displayVirtualMachine
      runningManifestURL = machine.manifestURL
      activityMessage = "Starting \(machine.name)"
      runTask = Task { [weak self] in
        do {
          try await newRunner.run()
          self?.activityMessage = "\(machine.name) stopped"
        } catch {
          self?.errorMessage = error.localizedDescription
          self?.activityMessage = "\(machine.name) failed"
        }
        self?.runner = nil
        self?.lifecycleLock = nil
        self?.consoleVirtualMachine = nil
        self?.runningManifestURL = nil
        self?.runTask = nil
      }
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func requestStop() {
    guard let runner else { return }
    do {
      guard try runner.requestStop() else {
        errorMessage = "The guest did not accept the stop request."
        return
      }
      activityMessage = "Waiting for the guest to stop"
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func forceStop() {
    guard let runner else { return }
    activityMessage = "Forcing virtual machine stop"
    Task {
      do {
        try await runner.forceStop()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  func enableMetal() {
    do {
      let previous = try HostMetalPreferenceManager().enable()
      activityMessage = "Metal bridge enabled; previous value was \(previous.description)"
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func restoreMetalPreference() {
    guard runningManifestURL == nil else {
      errorMessage = "Stop the running VM before restoring the host Metal preference."
      return
    }
    do {
      let restored = try HostMetalPreferenceManager().restore()
      activityMessage = "Restored Metal preference to \(restored.description)"
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
