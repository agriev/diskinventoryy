import SwiftUI

@main
struct DiskInventoryYApp: App {
    var body: some Scene {
        WindowGroup("DiskInventoryY", for: ScanID?.self) { $scanID in
            RootView(scanID: scanID ?? nil)
                .frame(minWidth: 900, minHeight: 600)
        } defaultValue: {
            // First launch / restored landing window opens with no scan.
            nil
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Scan…") {
                    NotificationCenter.default.post(name: .openFolderRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    /// Posted from the File → New Scan menu item; the focused window
    /// catches it and opens its file importer.
    static let openFolderRequested = Notification.Name("DiskInventoryY.openFolderRequested")
}
