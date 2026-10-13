import AppKit
import MyKit
import QuickLookUI

/// Space on a hovered thumbnail: the capture in Quick Look; Space again closes it.
final class QuickLookPreview: NSObject, QLPreviewPanelDataSource {
    private var file: URL?

    func toggle(_ file: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, self.file == file {
            panel.orderOut(nil)
            return
        }
        self.file = file
        panel.dataSource = self
        panel.reloadData()
        AppWindows.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { file as NSURL? }
    }
}
