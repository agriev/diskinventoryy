import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            TreemapSettingsView()
                .tabItem { Label("Treemap", systemImage: "rectangle.split.3x3") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480, height: 340)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Show hidden files", isOn: $settings.showHidden)
                .help("Include dotfiles and hidden directories during scans")
            Toggle("Show package contents", isOn: $settings.showPackageContents)
                .help("Recurse into bundles like .app and .xcodeproj instead of treating them as leaves")
            Picker("Size unit", selection: $settings.sizeUnitRaw) {
                Text("Binary (1024)").tag("binary")
                Text("Decimal (1000)").tag("decimal")
            }
            .pickerStyle(.segmented)
            .help("How to format byte counts in the UI")
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct TreemapSettingsView: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Cushion intensity: \(settings.cushionIntensity, format: .number.precision(.fractionLength(2)))")
                Slider(value: $settings.cushionIntensity, in: 0...1)
                    .help("How much top-left → bottom-right shading to apply per cell")
            }
            VStack(alignment: .leading) {
                Text("Depth contrast: \(settings.depthContrast, format: .number.precision(.fractionLength(2)))")
                Slider(value: $settings.depthContrast, in: 0...0.4)
                    .help("Per-depth darkening so nested folders stand out")
            }
            Toggle("Animate drill-in", isOn: $settings.animateZoom)
                .help("Cross-fade when zooming into a folder; ignored when Reduce Motion is on")
            Picker("Size mode", selection: $settings.sizeModeRaw) {
                Text("Logical").tag("logical")
                Text("Physical on disk").tag("physical")
            }
            .pickerStyle(.segmented)
            .help("Logical: file size as reported. Physical: bytes actually allocated on disk (APFS-compressed/sparse files differ).")
            Picker("Algorithm", selection: $settings.treemapAlgorithmRaw) {
                Text("Squarified").tag("squarified")
                Text("Slice & Dice (classic)").tag("sliceAndDice")
            }
            .pickerStyle(.segmented)
            .help("Squarified (Bruls/van Wijk, used by modern KDirStat) packs cells as close to square as possible. Slice & Dice (Shneiderman 1992, KDirStat 1.x style) uses alternating horizontal/vertical strips — easier to read, more elongated cells.")
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Telemetry", value: "Never collected")
                LabeledContent("Crash reports", value: "Never collected")
                LabeledContent("Network", value: "Disabled")
            } footer: {
                Text("DiskInventoryY runs entirely on-device. No data leaves your machine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
