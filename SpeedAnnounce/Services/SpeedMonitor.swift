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
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    let settings: AppSettings
    private let location = LocationService()
    private let announcer = Announcer()
    private var provider: SpeedLimitProvider
    private var providerKey: String
    private var policy = AnnouncementPolicy()
    private var lookupInFlight = false
    private var lastLookup = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []

    /// Minimum time between speed limit lookups.
    private let lookupInterval: TimeInterval = 1

    init(settings: AppSettings) {
        self.settings = settings
        self.provider = Self.makeProvider(settings)
        self.providerKey = Self.makeProviderKey(settings)

        location.onLocation = { [weak self] location in
            Task { @MainActor in self?.handle(location) }
        }
        location.onAuthorizationChange = { [weak self] status in
            Task { @MainActor in self?.authorizationStatus = status }
        }

        settings.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)
        applySettings()
        authorizationStatus = location.authorizationStatus
    }

    func start() {
        guard !isRunning else { return }
        location.requestPermission()
        policy.reset()
        currentLimit = nil
        statusMessage = "Søger efter vej…"
        isRunning = true
        location.start()
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

    private func applySettings() {
        policy.config.announceOnChange = settings.announceOnChange
        policy.config.periodicInterval = settings.periodicIntervalMinutes > 0
            ? TimeInterval(settings.periodicIntervalMinutes * 60) : nil
        policy.config.warnWhenSpeeding = settings.warnWhenSpeeding
        policy.config.toleranceKmh = Double(settings.speedingToleranceKmh)
        policy.config.warningRepeat = TimeInterval(max(settings.warningRepeatSeconds, 5))
        announcer.speechRate = settings.speechRate

        let key = Self.makeProviderKey(settings)
        if key != providerKey {
            providerKey = key
            provider = Self.makeProvider(settings)
        }
    }

    private static func makeProviderKey(_ settings: AppSettings) -> String {
        [settings.source.rawValue, settings.sapheEndpoint, settings.sapheAPIKey].joined(separator: "|")
    }

    private static func makeProvider(_ settings: AppSettings) -> SpeedLimitProvider {
        switch settings.source {
        case .openStreetMap: return OSMSpeedLimitProvider()
        case .saphe: return SapheSpeedLimitProvider(endpoint: settings.sapheEndpoint, apiKey: settings.sapheAPIKey)
        }
    }

    private func handle(_ location: CLLocation) {
        guard isRunning, location.horizontalAccuracy >= 0 else { return }
        let sample = LocationSample(location)
        speedKmh = sample.speedKmh
        handle(policy.tick(speedKmh: sample.speedKmh, at: Date()))
        updateSpeedingFlag()

        guard !lookupInFlight, location.horizontalAccuracy <= 100,
              Date().timeIntervalSince(lastLookup) >= lookupInterval else { return }
        lookupInFlight = true
        lastLookup = Date()
        let provider = self.provider
        Task {
            defer { lookupInFlight = false }
            do {
                let limit = try await provider.speedLimit(for: sample)
                guard isRunning else { return }
                roadName = limit?.roadName
                statusMessage = limit == nil && policy.confirmed == nil ? "Ukendt fartgrænse her" : nil
                handle(policy.observe(limit, at: Date()))
            } catch {
                statusMessage = error.localizedDescription
            }
            currentLimit = policy.confirmed
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
