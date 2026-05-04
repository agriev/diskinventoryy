import Foundation
import Observation

/// Single source of truth for user preferences. Keys mirror the strings
/// used by `@AppStorage` in `SettingsView` so existing values survive.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum SizeMode: String, Sendable {
        case logical, physical
    }

    enum SizeUnit: String, Sendable {
        case binary, decimal
    }

    private let defaults = UserDefaults.standard

    var showHidden: Bool {
        didSet { defaults.set(showHidden, forKey: "showHidden") }
    }
    var showPackageContents: Bool {
        didSet { defaults.set(showPackageContents, forKey: "showPackageContents") }
    }
    var sizeUnitRaw: String {
        didSet { defaults.set(sizeUnitRaw, forKey: "sizeUnit") }
    }
    var cushionIntensity: Double {
        didSet { defaults.set(cushionIntensity, forKey: "cushionIntensity") }
    }
    var depthContrast: Double {
        didSet { defaults.set(depthContrast, forKey: "depthContrast") }
    }
    var animateZoom: Bool {
        didSet { defaults.set(animateZoom, forKey: "animateZoom") }
    }
    var sizeModeRaw: String {
        didSet { defaults.set(sizeModeRaw, forKey: "sizeMode") }
    }

    var sizeUnit: SizeUnit { SizeUnit(rawValue: sizeUnitRaw) ?? .binary }
    var sizeMode: SizeMode { SizeMode(rawValue: sizeModeRaw) ?? .physical }

    init() {
        // Sensible defaults; first-launch values match what the
        // existing SettingsView showed.
        self.showHidden = defaults.object(forKey: "showHidden") as? Bool ?? true
        self.showPackageContents = defaults.object(forKey: "showPackageContents") as? Bool ?? false
        self.sizeUnitRaw = defaults.string(forKey: "sizeUnit") ?? "binary"
        self.cushionIntensity = defaults.object(forKey: "cushionIntensity") as? Double ?? 0.7
        self.depthContrast = defaults.object(forKey: "depthContrast") as? Double ?? 0.15
        self.animateZoom = defaults.object(forKey: "animateZoom") as? Bool ?? true
        self.sizeModeRaw = defaults.string(forKey: "sizeMode") ?? "physical"
    }

    /// Build the `ScanOptions` that reflect current settings.
    var scanOptions: ScanOptions {
        var opts = ScanOptions.default
        opts.includeHidden = showHidden
        opts.descendIntoPackages = showPackageContents
        return opts
    }
}
