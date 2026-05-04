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

                Divider()

                Button("Open Scan…") {
                    NotificationCenter.default.post(name: .openSavedScanRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Save Scan…") {
                    NotificationCenter.default.post(name: .saveScanRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    /// Posted from the File → New Scan menu item; the focused window
    /// catches it and opens its folder importer.
    static let openFolderRequested = Notification.Name("DiskInventoryY.openFolderRequested")
    /// Posted from File → Save Scan… — focused window writes its
    /// current `ScanResult` to a `.dscan` file.
    static let saveScanRequested = Notification.Name("DiskInventoryY.saveScanRequested")
    /// Posted from File → Open Scan… — focused window opens a
    /// `.dscan` importer.
    static let openSavedScanRequested = Notification.Name("DiskInventoryY.openSavedScanRequested")
}
