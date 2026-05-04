import AppKit

/// Shared right-click menu factory for cells in the treemap and rows
/// in the outline. Items dispatch into `FileActions`.
enum ItemContextMenu {
    @MainActor
    static func make(for node: FSNode, onTrash: ((FSNode) -> Void)? = nil) -> NSMenu? {
        guard !node.isSynthetic else { return nil }

        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Reveal in Finder") {
            FileActions.revealInFinder(node.url)
        })
        menu.addItem(ClosureMenuItem("Quick Look") {
            FileActions.quickLook(node.url)
        })
        menu.addItem(ClosureMenuItem("Open with Default App") {
            FileActions.openWithDefaultApp(node.url)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        })
        menu.addItem(ClosureMenuItem("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.displayName, forType: .string)
        })
        menu.addItem(.separator())
        let trashItem = ClosureMenuItem("Move to Trash") {
            if let onTrash {
                onTrash(node)
            } else {
                _ = try? FileActions.moveToTrash(node.url)
            }
        }
        menu.addItem(trashItem)
        return menu
    }
}

/// `NSMenuItem` subclass that holds a closure action; saves us from
/// having to thread targets/selectors through every menu user.
final class ClosureMenuItem: NSMenuItem {
    private let block: () -> Void

    init(_ title: String, keyEquivalent: String = "", _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        self.target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    @objc private func invoke() {
        block()
    }
}
