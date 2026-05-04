import Foundation
import Observation

/// Persists the last-N scan roots in `UserDefaults`. Lives on the main
/// actor since views read it directly.
@MainActor
@Observable
final class RecentsStore {
    static let shared = RecentsStore()

    private(set) var entries: [Entry] = []

    private let defaults = UserDefaults.standard
    private let key = "diskinventoryy.recents"
    private let maxEntries = 20

    struct Entry: Codable, Hashable, Identifiable, Sendable {
        var url: URL
        var displayName: String
        var lastScanned: Date
        var totalBytes: Int64

        var id: URL { url }
    }

    init() {
        load()
    }

    func record(_ entry: Entry) {
        entries.removeAll { $0.url == entry.url }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func remove(_ url: URL) {
        entries.removeAll { $0.url == url }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
