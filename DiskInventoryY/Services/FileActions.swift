import AppKit
import Foundation
import Quartz

/// Side-effecting actions invoked from the Inspector and context menus.
/// Wraps NSWorkspace + FileManager and a tiny QLPreviewPanel coordinator.
enum FileActions {

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openWithDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    static func moveToTrash(_ url: URL) throws -> URL? {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    /// Show / hide the system-wide Quick Look panel. The data source
    /// stays alive on the singleton so the panel can keep asking it
    /// for the preview URL.
    static func quickLook(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        QuickLookCoordinator.shared.previewURL = url
        if !panel.isVisible {
            panel.dataSource = QuickLookCoordinator.shared
            panel.delegate = QuickLookCoordinator.shared
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.reloadData()
        }
    }
}

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    var previewURL: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as NSURL? ?? URL(fileURLWithPath: "/") as NSURL
    }
}
