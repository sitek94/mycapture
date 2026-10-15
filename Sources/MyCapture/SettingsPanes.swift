import MyCaptureCore
import MyKit
import SwiftUI

/// The panes of the Settings window, in the series order: General, the app's own, Permissions, About.
enum SettingsPanes {
    static func all(_ app: AppModel) -> [SettingsPane] {
        [
            SettingsPane("General", icon: .general) { GeneralPane(app: app) },
            SettingsPane("Shortcuts", icon: .shortcuts) { ShortcutsPane(app: app) },
            SettingsPane("History", icon: .history) { HistoryPane(history: app.history) },
            SettingsPane("Permissions", icon: .permissions) {
                PermissionRow("Screen Recording", granted: app.screenRecordingAllowed) {
                    SystemSettingsPane.screenRecording.open()
                }
            },
            SettingsPane("About", icon: .about) { AboutRow() },
        ]
    }
}

private struct GeneralPane: View {
    @Bindable var app: AppModel

    var body: some View {
        Section {
            LaunchAtLoginToggle()
        }
        Section("Capture") {
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
    }
}

private struct ShortcutsPane: View {
    let app: AppModel

    var body: some View {
        Section {
            LabeledContent("Capture Area") { ShortcutRecorder(app.areaShortcut) }
            LabeledContent("Capture Area to Clipboard") { ShortcutRecorder(app.clipboardShortcut) }
            LabeledContent("Capture Window") { ShortcutRecorder(app.windowShortcut) }
            LabeledContent("Restore Last Capture") { ShortcutRecorder(app.restoreShortcut) }
            LabeledContent("Open Capture History") { ShortcutRecorder(app.historyShortcut) }
        }
    }
}

private struct HistoryPane: View {
    @Bindable var history: HistoryController

    var body: some View {
        Section {
            Picker("Keep history", selection: $history.retention) {
                ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LabeledContent("\(history.entries.count) captures") {
                Button("Clear History", role: .destructive) { history.clear() }
                    .disabled(history.entries.isEmpty)
            }
        } footer: {
            Text("Captures older than this leave the history. Saved files stay where you saved them.")
                .font(.textCaption)
                .foregroundStyle(.secondary)
        }
    }
}
