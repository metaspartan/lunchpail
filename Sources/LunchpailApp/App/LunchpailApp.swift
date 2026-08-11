import AppKit
import SwiftUI

final class LunchpailAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@main
struct LunchpailDesktopApp: App {
  @NSApplicationDelegateAdaptor(LunchpailAppDelegate.self) private var appDelegate
  @State private var model = LunchpailAppModel()

  var body: some Scene {
    WindowGroup("Lunchpail", id: "main") {
      ContentView(model: model)
        .frame(minWidth: 900, minHeight: 620)
        .task { model.refresh() }
    }
    .defaultSize(width: 1080, height: 720)
    .commands {
      CommandMenu("Virtual Machine") {
        Button("Refresh") { model.refresh() }
          .keyboardShortcut("r")
        Divider()
        Button("Stop Running VM") { model.requestStop() }
          .disabled(model.runningManifestURL == nil)
          .keyboardShortcut(".")
      }
    }

    Window("VM Console", id: "vm-console") {
      VMConsoleView(model: model)
        .frame(minWidth: 720, minHeight: 480)
    }
    .defaultSize(width: 1280, height: 800)
    .windowResizability(.contentMinSize)

    Settings {
      SettingsView()
    }
  }
}
