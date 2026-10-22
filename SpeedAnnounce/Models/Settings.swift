import Foundation

enum SpeedLimitSourceKind: String, CaseIterable, Identifiable {
    case openStreetMap
    case saphe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openStreetMap: return "OpenStreetMap"
        case .saphe: return "Saphe (kræver API-adgang)"
        }
    }
}

/// User settings, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var announceOnChange: Bool { didSet { defaults.set(announceOnChange, forKey: Keys.announceOnChange) } }
    /// Minutes between periodic announcements; 0 disables them.
    @Published var periodicIntervalMinutes: Int { didSet { defaults.set(periodicIntervalMinutes, forKey: Keys.periodic) } }
    @Published var warnWhenSpeeding: Bool { didSet { defaults.set(warnWhenSpeeding, forKey: Keys.warn) } }
    /// km/h above the limit that is tolerated before warning.
    @Published var speedingToleranceKmh: Int { didSet { defaults.set(speedingToleranceKmh, forKey: Keys.tolerance) } }
    /// Seconds between repeated warnings while still speeding.
    @Published var warningRepeatSeconds: Int { didSet { defaults.set(warningRepeatSeconds, forKey: Keys.warnRepeat) } }
    @Published var playWarningTone: Bool { didSet { defaults.set(playWarningTone, forKey: Keys.tone) } }
    @Published var speechRate: Float { didSet { defaults.set(speechRate, forKey: Keys.rate) } }
    @Published var source: SpeedLimitSourceKind { didSet { defaults.set(source.rawValue, forKey: Keys.source) } }
    @Published var sapheAPIKey: String { didSet { defaults.set(sapheAPIKey, forKey: Keys.sapheKey) } }
    @Published var sapheEndpoint: String { didSet { defaults.set(sapheEndpoint, forKey: Keys.sapheEndpoint) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.announceOnChange: true,
            Keys.periodic: 0,
            Keys.warn: true,
            Keys.tolerance: 3,
            Keys.warnRepeat: 20,
            Keys.tone: true,
            Keys.rate: 0.5,
            Keys.source: SpeedLimitSourceKind.openStreetMap.rawValue,
        ])
        announceOnChange = defaults.bool(forKey: Keys.announceOnChange)
        periodicIntervalMinutes = defaults.integer(forKey: Keys.periodic)
        warnWhenSpeeding = defaults.bool(forKey: Keys.warn)
        speedingToleranceKmh = defaults.integer(forKey: Keys.tolerance)
        warningRepeatSeconds = defaults.integer(forKey: Keys.warnRepeat)
        playWarningTone = defaults.bool(forKey: Keys.tone)
        speechRate = defaults.float(forKey: Keys.rate)
        source = SpeedLimitSourceKind(rawValue: defaults.string(forKey: Keys.source) ?? "") ?? .openStreetMap
        sapheAPIKey = defaults.string(forKey: Keys.sapheKey) ?? ""
        sapheEndpoint = defaults.string(forKey: Keys.sapheEndpoint) ?? ""
    }

    private enum Keys {
        static let announceOnChange = "announceOnChange"
        static let periodic = "periodicIntervalMinutes"
        static let warn = "warnWhenSpeeding"
        static let tolerance = "speedingToleranceKmh"
        static let warnRepeat = "warningRepeatSeconds"
        static let tone = "playWarningTone"
        static let rate = "speechRate"
        static let source = "speedLimitSource"
        static let sapheKey = "sapheAPIKey"
        static let sapheEndpoint = "sapheEndpoint"
    }
}
