import Combine
import CoreLocation

/// Ties location, speed limit lookups and announcements together.
@MainActor
final class SpeedMonitor: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var currentLimit: AnnouncementPolicy.Limit?
    @Published private(set) var roadName: String?
    @Published private(set) var speedKmh: Double?
    @Published private(set) var isSpeeding = false
    @Published private(set) var statusMessage: String?
    /// Name of the source that produced the current limit.
    @Published private(set) var limitSource: String?
    @Published private(set) var hereRequestsThisMonth = 0
    @Published private(set) var diagnostics = Diagnostics()

    /// What the app is doing right now, shown under Indstillinger → Diagnose.
    struct Diagnostics {
        var locationsReceived = 0
        var lastFix: Date?
        var lastAccuracy: Double?
        var lookupsStarted = 0
        var lookupsFinished = 0
        var lastLookupDuration: TimeInterval?
        var lastLookupResult: String?
        var lastError: String?
        var hereStatus: String?
    }
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    let settings: AppSettings
    private let location = LocationService()
    private let announcer = Announcer()
    private var provider: SpeedLimitProvider
    private var providerKey: String
    private let hereUsage: HEREUsage
    private var policy = AnnouncementPolicy()
    private var lookupInFlight = false
    private var lastLookup = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []

    /// Minimum time between speed limit lookups.
    private let lookupInterval: TimeInterval = 1
    /// Fixes less precise than this are not used for lookups.
    private let maxLookupAccuracy: CLLocationAccuracy = 100

    init(settings: AppSettings) {
        self.settings = settings
        let hereUsage = HEREUsage(monthlyLimit: settings.hereMonthlyLimit)
        self.hereUsage = hereUsage
        self.provider = Self.makeProvider(settings, hereUsage: hereUsage)
        self.providerKey = Self.makeProviderKey(settings)

        location.onLocation = { [weak self] location in
            Task { @MainActor in self?.handle(location) }
        }
        location.onAuthorizationChange = { [weak self] status in
            Task { @MainActor in self?.authorizationChanged(status) }
        }

        settings.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)
        applySettings()
        authorizationStatus = location.authorizationStatus
        hereRequestsThisMonth = hereUsage.thisMonth
    }

    func start() {
        guard !isRunning else { return }
        location.requestPermission()
        policy.reset()
        currentLimit = nil
        diagnostics = Diagnostics()
        isRunning = true
        location.start()
        updateWaitingMessage()
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        guard isRunning else { return }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            // Updates requested before permission was granted are not always delivered; ask again.
            location.start()
        }
        updateWaitingMessage()
    }

    /// Explains why there is no limit yet, so a stuck state can be diagnosed.
    private func updateWaitingMessage() {
        guard isRunning, policy.confirmed == nil else { return }
        switch authorizationStatus {
        case .denied, .restricted:
            statusMessage = "Ingen adgang til lokalitet. Slå det til under Indstillinger → Fartgrænse."
            return
        case .notDetermined:
            statusMessage = "Venter på tilladelse til lokalitet…"
            return
        default:
            break
        }
        if diagnostics.locationsReceived == 0 {
            statusMessage = "Venter på GPS…"
        } else if let accuracy = diagnostics.lastAccuracy, accuracy > maxLookupAccuracy {
            statusMessage = "Svagt GPS-signal (±\(Int(accuracy)) m). Venter på bedre signal…"
        } else if lookupInFlight {
            statusMessage = "Henter fartgrænse…"
        }
    }

    func stop() {
        location.stop()
        isRunning = false
        isSpeeding = false
        speedKmh = nil
        statusMessage = nil
    }

    func testAnnouncement() {
        announcer.announce(.limitChanged(currentLimit ?? .kmh(80)))
    }

    func testWarning() {
        announcer.announce(.speeding(limit: 50, speed: 62), withTone: settings.playWarningTone)
    }

    /// Fills the screen with sample values, used for App Store/README screenshots.
    func showDemo(limit: Int, speed: Double, road: String) {
        currentLimit = .kmh(limit)
        speedKmh = speed
        roadName = road
        isRunning = true
        isSpeeding = speed > Double(limit + settings.speedingToleranceKmh)
    }

    private func applySettings() {
        policy.config.announceOnChange = settings.announceOnChange
        policy.config.periodicInterval = settings.periodicIntervalMinutes > 0
            ? TimeInterval(settings.periodicIntervalMinutes * 60) : nil
        policy.config.warnWhenSpeeding = settings.warnWhenSpeeding
        policy.config.toleranceKmh = Double(settings.speedingToleranceKmh)
        policy.config.warningRepeat = TimeInterval(max(settings.warningRepeatSeconds, 5))
        announcer.speechRate = settings.speechRate
        hereUsage.monthlyLimit = settings.hereMonthlyLimit

        let key = Self.makeProviderKey(settings)
        if key != providerKey {
            providerKey = key
            provider = Self.makeProvider(settings, hereUsage: hereUsage)
        }
    }

    private static func makeProviderKey(_ settings: AppSettings) -> String {
        [settings.source.rawValue, settings.sapheEndpoint, settings.sapheAPIKey, settings.hereAPIKey].joined(separator: "|")
    }

    private static func makeProvider(_ settings: AppSettings, hereUsage: HEREUsage) -> SpeedLimitProvider {
        switch settings.source {
        case .here:
            return FallbackSpeedLimitProvider(
                primary: HERESpeedLimitProvider(apiKey: settings.hereAPIKey, usage: hereUsage),
                fallback: OSMSpeedLimitProvider())
        case .hereOnly:
            return HERESpeedLimitProvider(apiKey: settings.hereAPIKey, usage: hereUsage)
        case .openStreetMap: return OSMSpeedLimitProvider()
        case .saphe: return SapheSpeedLimitProvider(endpoint: settings.sapheEndpoint, apiKey: settings.sapheAPIKey)
        }
    }

    private func handle(_ location: CLLocation) {
        guard isRunning, location.horizontalAccuracy >= 0 else { return }
        diagnostics.locationsReceived += 1
        diagnostics.lastFix = location.timestamp
        diagnostics.lastAccuracy = location.horizontalAccuracy
        let sample = LocationSample(location)
        speedKmh = sample.speedKmh
        handle(policy.tick(speedKmh: sample.speedKmh, at: Date()))
        updateSpeedingFlag()

        defer { updateWaitingMessage() }
        guard !lookupInFlight, location.horizontalAccuracy <= maxLookupAccuracy,
              Date().timeIntervalSince(lastLookup) >= lookupInterval else { return }
        lookupInFlight = true
        lastLookup = Date()
        diagnostics.lookupsStarted += 1
        let provider = self.provider
        let started = Date()
        Task {
            defer {
                lookupInFlight = false
                diagnostics.lookupsFinished += 1
                diagnostics.lastLookupDuration = Date().timeIntervalSince(started)
            }
            do {
                let limit = try await provider.speedLimit(for: sample)
                diagnostics.hereStatus = (provider as? FallbackSpeedLimitProvider)?.primaryStatus
                    ?? (provider is HERESpeedLimitProvider ? limit.map { $0.kmh.map { "\($0) km/t" } ?? "ingen grænse" } : nil)
                diagnostics.lastLookupResult = limit.map { "\($0.kmh.map { "\($0)" } ?? "ingen grænse") km/t fra \($0.source)" }
                    ?? "ukendt fartgrænse"
                diagnostics.lastError = nil
                guard isRunning else { return }
                roadName = limit?.roadName
                limitSource = limit?.source ?? limitSource
                statusMessage = limit == nil && policy.confirmed == nil ? "Ukendt fartgrænse her" : nil
                if let error = (provider as? FallbackSpeedLimitProvider)?.primaryError {
                    statusMessage = "HERE: \(error.localizedDescription)"
                }
                handle(policy.observe(limit, at: Date()))
            } catch {
                diagnostics.lastLookupResult = "fejl"
                diagnostics.hereStatus = (provider as? FallbackSpeedLimitProvider)?.primaryStatus
                    ?? (provider is HERESpeedLimitProvider ? "fejl: \(error.localizedDescription)" : nil)
                diagnostics.lastError = error.localizedDescription
                statusMessage = error.localizedDescription
                // A failed lookup counts as unknown, so a stale limit expires after the grace period.
                if isRunning { handle(policy.observe(nil, at: Date())) }
            }
            currentLimit = policy.confirmed
            hereRequestsThisMonth = hereUsage.thisMonth
            updateSpeedingFlag()
        }
    }

    private func handle(_ events: [AnnouncementPolicy.Event]) {
        for event in events {
            announcer.announce(event, withTone: settings.playWarningTone)
        }
        currentLimit = policy.confirmed
    }

    private func updateSpeedingFlag() {
        if case .kmh(let limit) = policy.confirmed, let speedKmh {
            isSpeeding = speedKmh > Double(limit) + Double(settings.speedingToleranceKmh)
        } else {
            isSpeeding = false
        }
    }
}
