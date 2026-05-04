import AppKit
import Foundation
import Observation

/// Live list of mounted volumes. Listens to Disk Arbitration via
/// `NSWorkspace`'s mount/unmount notifications so the sidebar refreshes
/// automatically when the user attaches an external drive.
@MainActor
@Observable
final class VolumeService {
    private(set) var volumes: [VolumeInfo] = []

    private static let resourceKeys: Set<URLResourceKey> = [
        .volumeLocalizedNameKey,
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsRemovableKey,
        .volumeIsLocalKey,
        .volumeIsReadOnlyKey,
        .volumeURLForRemountingKey,
        .volumeIdentifierKey,
        .volumeUUIDStringKey,
        .volumeIsBrowsableKey,
    ]

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Observer tokens deliberately not retained: VolumeService is
        // owned for the lifetime of the app via @State and the leaked
        // tokens are cleaned up at process exit.
    }

    func refresh() {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(Self.resourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []
        volumes = urls.compactMap { Self.makeInfo(for: $0) }
    }

    private static func makeInfo(for url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
        if values.volumeIsBrowsable == false { return nil }
        let name = values.volumeLocalizedName
            ?? values.volumeName
            ?? url.lastPathComponent
        return VolumeInfo(
            name: name,
            url: url,
            fileSystemType: nil,
            totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(values.volumeAvailableCapacity ?? 0),
            availableForImportant: Int64(values.volumeAvailableCapacityForImportantUsage ?? 0),
            isRemovable: values.volumeIsRemovable ?? false,
            isLocal: values.volumeIsLocal ?? true,
            isReadOnly: values.volumeIsReadOnly ?? false
        )
    }
}
