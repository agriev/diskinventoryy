import SwiftUI

@main
struct DiskInventoryYApp: App {
    var body: some Scene {
        WindowGroup("DiskInventoryY") {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
        }
    }
}
