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
        .frame(width: 480, height: 320)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("showHidden") private var showHidden = false
    @AppStorage("showPackageContents") private var showPackageContents = false
    @AppStorage("sizeUnit") private var sizeUnit = "binary"

    var body: some View {
        Form {
            Toggle("Show hidden files", isOn: $showHidden)
            Toggle("Show package contents", isOn: $showPackageContents)
            Picker("Size unit", selection: $sizeUnit) {
                Text("Binary (1024)").tag("binary")
                Text("Decimal (1000)").tag("decimal")
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct TreemapSettingsView: View {
    @AppStorage("cushionIntensity") private var cushionIntensity = 0.7
    @AppStorage("depthContrast") private var depthContrast = 0.15
    @AppStorage("animateZoom") private var animateZoom = true
    @AppStorage("sizeMode") private var sizeMode = "physical"

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Cushion intensity: \(cushionIntensity, format: .number.precision(.fractionLength(2)))")
                Slider(value: $cushionIntensity, in: 0...1)
            }
            VStack(alignment: .leading) {
                Text("Depth contrast: \(depthContrast, format: .number.precision(.fractionLength(2)))")
                Slider(value: $depthContrast, in: 0...0.4)
            }
            Toggle("Animate drill-in", isOn: $animateZoom)
            Picker("Size mode", selection: $sizeMode) {
                Text("Logical").tag("logical")
                Text("Physical on disk").tag("physical")
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Text("Telemetry: never collected. Privacy by default.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
