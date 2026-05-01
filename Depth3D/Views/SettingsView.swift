import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = ScanSettings.shared
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                cameraCaptureSection
                defaultsSection
                storageSection
                deviceSection
                resetSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var cameraCaptureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Capture Interval")
                    Spacer()
                    Text("\(Int(settings.captureIntervalMs)) ms")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.captureIntervalMs, in: 100...1000, step: 50)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Image Resolution")
                    Spacer()
                    Text("\(Int(settings.downsampleScale * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.downsampleScale, in: 0.1...0.5, step: 0.05)
            }

            Stepper(
                "Max Captures: \(settings.maxCaptures)",
                value: $settings.maxCaptures,
                in: 50...500,
                step: 50
            )
        } header: {
            Text("Camera Capture")
        } footer: {
            Text("More frequent captures and higher resolution improve color accuracy on the final 3D model but use more memory during scanning.")
        }
    }

    private var defaultsSection: some View {
        Section {
            HStack {
                Text("Default Name")
                Spacer()
                TextField("Scan", text: $settings.defaultNamePrefix)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Defaults")
        } footer: {
            Text("Used when you don't enter a name. Numbers are appended automatically (e.g. \"\(settings.defaultNamePrefix) 1\", \"\(settings.defaultNamePrefix) 2\").")
        }
    }

    private var storageSection: some View {
        Section {
            HStack {
                Image(systemName: store.isUsingICloud ? "icloud.fill" : "iphone")
                    .foregroundStyle(store.isUsingICloud ? .blue : .secondary)
                Text(store.isUsingICloud ? "iCloud Drive" : "On This iPhone")
                Spacer()
                Text(store.isUsingICloud ? "Synced" : "Local")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Storage")
        } footer: {
            Text(store.isUsingICloud
                 ? "Your scans sync to all devices signed in to your iCloud account."
                 : "Sign in to iCloud and enable iCloud Drive to sync scans across devices.")
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            HStack {
                Image(systemName: lidarIcon)
                    .foregroundStyle(LiDARScanner.isLiDARAvailable ? .green : .orange)
                Text("LiDAR Sensor")
                Spacer()
                Text(LiDARScanner.isLiDARAvailable ? "Available" : "Not Found")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0").foregroundStyle(.secondary)
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                settings.resetToDefaults()
            } label: {
                HStack {
                    Spacer()
                    Text("Reset to Defaults")
                    Spacer()
                }
            }
        }
    }

    private var lidarIcon: String {
        LiDARScanner.isLiDARAvailable
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }
}
