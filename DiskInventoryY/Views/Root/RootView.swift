import SwiftUI

struct RootView: View {
    @State private var sidebarSelection: SidebarItem? = .empty
    @State private var inspectorVisible = false

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section("Drives") {
                    Label("No volumes yet", systemImage: "externaldrive")
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.empty)
                }
                Section("Recent Scans") {
                    Label("No recent scans", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            EmptyStateView()
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            // wired up in subsequent iterations
                        } label: {
                            Label("Open Volume", systemImage: "folder.badge.plus")
                        }
                        .help("Open a folder or volume to scan")

                        Button {
                            inspectorVisible.toggle()
                        } label: {
                            Label("Inspector", systemImage: "sidebar.right")
                        }
                        .help("Toggle inspector")
                    }
                }
        }
        .inspector(isPresented: $inspectorVisible) {
            InspectorPlaceholderView()
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
    }
}

enum SidebarItem: Hashable {
    case empty
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("No scan yet")
                .font(.title2)
            Text("Open a folder or volume from the toolbar to begin scanning.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InspectorPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select an item to inspect")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    RootView()
        .frame(width: 1100, height: 700)
}
