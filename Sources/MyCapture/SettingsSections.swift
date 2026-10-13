import MyKit
import SwiftUI

/// The sections of the Settings window.
struct SettingsSections: View {
    @Bindable var app: AppModel

    var body: some View {
        Section("General") {
            LaunchAtLoginToggle()
            LabeledContent("Capture Area") { ShortcutRecorder(app.areaShortcut) }
            LabeledContent("Capture Area to Clipboard") { ShortcutRecorder(app.clipboardShortcut) }
            LabeledContent("Capture Window") { ShortcutRecorder(app.windowShortcut) }
            LabeledContent("Restore Last Capture") { ShortcutRecorder(app.restoreShortcut) }
            Toggle("Freeze screen during area capture", isOn: $app.freezeScreen)
            Toggle("Play sound", isOn: $app.playSound)
        }

        Section("Saving") {
            LabeledContent("Screenshots folder") {
                HStack(spacing: .space2) {
                    Text(app.saveFolder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { app.chooseSaveFolder() }
                }
            }
        }

        Section("Permissions") {
            PermissionRow("Screen Recording", granted: app.screenRecordingAllowed) {
                SystemSettingsPane.screenRecording.open()
            }
        }

        Section("About") {
            AboutRow()
        }
    }
}
