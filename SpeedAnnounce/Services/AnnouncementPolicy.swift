import Foundation

/// Decides *when* to announce. Pure logic without side effects, so it can be unit tested.
struct AnnouncementPolicy {
    struct Config: Equatable {
        var announceOnChange = true
        /// `nil` disables periodic announcements.
        var periodicInterval: TimeInterval?
        var warnWhenSpeeding = true
        var toleranceKmh = 3.0
        var warningRepeat: TimeInterval = 20
        /// Consecutive identical lookups needed before a new limit is accepted.
        var confirmationsNeeded = 2
        /// ...and the new value must have been seen for at least this long.
        var minCandidateDuration: TimeInterval = 1
        /// Going back to the limit that was just replaced needs much stronger evidence,
        /// so two sources or two nearby roads can't make the limit flip back and forth.
        var flipBackDuration: TimeInterval = 8
        /// How long after a change a return to the previous limit counts as a flip back.
        var flipBackWindow: TimeInterval = 30
        /// How long a confirmed limit survives lookups that return "unknown".
        var unknownGrace: TimeInterval = 20
        /// Over-speed must last this long before warning (filters GPS spikes).
        var speedingDelay: TimeInterval = 2
        /// No warnings right after a limit change, so the driver has time to slow down.
        var gracePeriodAfterChange: TimeInterval = 5
    }

    enum Limit: Equatable {
        case kmh(Int)
        case unlimited

        init(_ limit: SpeedLimit) {
            self = limit.kmh.map(Limit.kmh) ?? .unlimited
        }
    }

    enum Event: Equatable {
        case limitChanged(Limit)
        case periodic(Limit)
        case speeding(limit: Int, speed: Int)
        case limitLost
    }

    var config: Config
    private(set) var confirmed: Limit?
    private var candidate: Limit?
    private var candidateCount = 0
    private var candidateSince: Date?
    private var previousConfirmed: Limit?
    private var confirmedAt: Date?
    private var lastKnownAt: Date?
    private var lastLimitAnnouncement: Date?
    private var overSince: Date?
    private var lastWarning: Date?

    init(config: Config = Config()) {
        self.config = config
    }

    /// Feed the result of a speed limit lookup.
    mutating func observe(_ limit: SpeedLimit?, at now: Date) -> [Event] {
        guard let limit else {
            if confirmed != nil, let lastKnownAt, now.timeIntervalSince(lastKnownAt) > config.unknownGrace {
                reset()
                return [.limitLost]
            }
            candidate = nil
            candidateCount = 0
            return []
        }

        let value = Limit(limit)
        lastKnownAt = now
        if value == confirmed {
            candidate = nil
            candidateCount = 0
            return []
        }
        if value == candidate {
            candidateCount += 1
        } else {
            candidate = value
            candidateCount = 1
            candidateSince = now
        }
        let isFlipBack = value == previousConfirmed
            && confirmedAt.map { now.timeIntervalSince($0) < config.flipBackWindow } ?? false
        let required = isFlipBack ? config.flipBackDuration : config.minCandidateDuration
        guard candidateCount >= config.confirmationsNeeded,
              now.timeIntervalSince(candidateSince ?? now) >= required else { return [] }

        previousConfirmed = confirmed
        confirmed = value
        confirmedAt = now
        candidate = nil
        candidateCount = 0
        overSince = nil
        lastWarning = nil
        guard config.announceOnChange else { return [] }
        lastLimitAnnouncement = now
        return [.limitChanged(value)]
    }

    /// Call for every location update.
    mutating func tick(speedKmh: Double?, at now: Date) -> [Event] {
        guard let confirmed else { return [] }
        var events: [Event] = []

        if let interval = config.periodicInterval, interval > 0 {
            let reference = lastLimitAnnouncement ?? confirmedAt ?? now
            if now.timeIntervalSince(reference) >= interval {
                lastLimitAnnouncement = now
                events.append(.periodic(confirmed))
            }
        }

        guard config.warnWhenSpeeding, case .kmh(let limit) = confirmed, let speedKmh else {
            overSince = nil
            return events
        }
        guard speedKmh > Double(limit) + config.toleranceKmh else {
            overSince = nil
            lastWarning = nil
            return events
        }
        let start = overSince ?? now
        overSince = start
        let inGrace = confirmedAt.map { now.timeIntervalSince($0) < config.gracePeriodAfterChange } ?? false
        let dueAgain = lastWarning.map { now.timeIntervalSince($0) >= config.warningRepeat } ?? true
        if !inGrace, now.timeIntervalSince(start) >= config.speedingDelay, dueAgain {
            lastWarning = now
            events.append(.speeding(limit: limit, speed: Int(speedKmh.rounded())))
        }
        return events
    }

    mutating func reset() {
        self = AnnouncementPolicy(config: config)
    }
}
