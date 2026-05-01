import Foundation
import Combine

/// User-configurable scan settings persisted to `UserDefaults`.
/// Accessed as `ScanSettings.shared` from non-view code (scanner coordinator,
/// LiDAR scanner) and via `@StateObject` / `@EnvironmentObject` in views.
final class ScanSettings: ObservableObject {
    static let shared = ScanSettings()

    @Published var captureIntervalMs: Double {
        didSet { UserDefaults.standard.set(captureIntervalMs, forKey: Keys.captureIntervalMs) }
    }

    @Published var downsampleScale: Double {
        didSet { UserDefaults.standard.set(downsampleScale, forKey: Keys.downsampleScale) }
    }

    @Published var defaultNamePrefix: String {
        didSet { UserDefaults.standard.set(defaultNamePrefix, forKey: Keys.defaultNamePrefix) }
    }

    @Published var maxCaptures: Int {
        didSet { UserDefaults.standard.set(maxCaptures, forKey: Keys.maxCaptures) }
    }

    private enum Keys {
        static let captureIntervalMs = "depth3d.captureIntervalMs"
        static let downsampleScale   = "depth3d.downsampleScale"
        static let defaultNamePrefix = "depth3d.defaultNamePrefix"
        static let maxCaptures       = "depth3d.maxCaptures"
    }

    // Default values
    static let defaultCaptureIntervalMs: Double = 300
    static let defaultDownsampleScale: Double = 0.25
    static let defaultNamePrefixValue: String = "Scan"
    static let defaultMaxCaptures: Int = 200

    private init() {
        let d = UserDefaults.standard
        captureIntervalMs = (d.object(forKey: Keys.captureIntervalMs) as? Double) ?? Self.defaultCaptureIntervalMs
        downsampleScale   = (d.object(forKey: Keys.downsampleScale) as? Double) ?? Self.defaultDownsampleScale
        defaultNamePrefix = d.string(forKey: Keys.defaultNamePrefix) ?? Self.defaultNamePrefixValue
        maxCaptures       = (d.object(forKey: Keys.maxCaptures) as? Int) ?? Self.defaultMaxCaptures
    }

    func resetToDefaults() {
        captureIntervalMs = Self.defaultCaptureIntervalMs
        downsampleScale   = Self.defaultDownsampleScale
        defaultNamePrefix = Self.defaultNamePrefixValue
        maxCaptures       = Self.defaultMaxCaptures
    }
}
