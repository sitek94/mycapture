import AppKit
import MyKit
import SwiftUI

@main
struct MyCaptureApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarItem("myCapture", image: MenuBarGlyph.image) {
            AppActions(app: delegate.app)
            Divider()
            AppMenuItems(appName: "myCapture", openSettings: delegate.app.showSettings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.start()
    }
}

/// myCapture's menu items. Each shows its global shortcut as the user set it.
struct AppActions: View {
    @Bindable var app: AppModel

    var body: some View {
        Button("Capture Area") { app.capture(.area, to: .thumbnail) }
            .keyboardShortcut(app.areaShortcut.shortcut?.menuShortcut)
        Button("Capture Area to Clipboard") { app.capture(.area, to: .clipboard) }
            .keyboardShortcut(app.clipboardShortcut.shortcut?.menuShortcut)
        Button("Capture Window") { app.capture(.window, to: .thumbnail) }
            .keyboardShortcut(app.windowShortcut.shortcut?.menuShortcut)
        Button("Restore Last Capture") { app.restoreLast() }
            .keyboardShortcut(app.restoreShortcut.shortcut?.menuShortcut)
        Divider()
        Button("Open Screenshots Folder") { app.openSaveFolder() }
        if !app.screenRecordingAllowed {
            Button("Allow Screen Recording…") { SystemSettingsPane.screenRecording.open() }
        }
    }
}
