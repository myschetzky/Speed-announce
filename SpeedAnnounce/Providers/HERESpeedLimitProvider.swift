import CoreLocation

/// Speed limits from the HERE Routing API (the same map data Saphe uses).
///
/// Instead of one request per GPS fix, it asks for a short route ahead in the
/// direction of travel with the speed limit of every stretch, and follows that
/// route locally. A new route is fetched only when the car leaves it (a turn)
/// or approaches its end, typically one request per 1–2 km.
final class HERESpeedLimitProvider: SpeedLimitProvider {
    let name = "HERE"

    private let apiKey: String
    private let session: URLSession
    private let usage: HEREUsage
    private var path: HERERoutePath?
    private var lastMatchIndex = 0
    private var lastFetch = Date.distantPast
    private var lastFetchCoordinate: CLLocationCoordinate2D?
    private var driftCount = 0
    /// Limits refetches caused by drift, in case a road's geometry is offset everywhere.
    private var driftRetryAfter = Date.distantPast
    /// A route segment this far away is probably a different, parallel road.
    private let driftDistance = 15.0
    /// After HERE rejects a request, wait before trying again so a bad request can't drain the quota.
    private var blockedUntil = Date.distantPast

    /// How far ahead the requested route reaches.
    private let lookahead = 1_500.0
    /// Fetch a new route when less than this remains on the current one.
    private let refetchRemaining = 300.0
    /// Minimum time between requests, so a GPS glitch can't burn through the quota.
    private let minFetchInterval: TimeInterval = 4

    init(apiKey: String, usage: HEREUsage, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.usage = usage
        self.session = session
    }

    func speedLimit(for sample: LocationSample) async throws -> SpeedLimit? {
        guard !apiKey.isEmpty else {
            throw SpeedLimitProviderError.notConfigured("Indtast din HERE API-nøgle under Indstillinger.")
        }
        let current = match(sample)
        let drifting = driftCount >= 3 && Date() >= driftRetryAfter
        if let current, current.remaining > refetchRemaining, !drifting {
            return try limit(from: current)
        }
        guard Date().timeIntervalSince(lastFetch) >= minFetchInterval else {
            return try current.map(limit(from:))
        }
        // Parked away from the road: a new route from the same spot would not match either.
        if current == nil, let last = lastFetchCoordinate,
           RoadGeometry.distance(last, sample.coordinate) < 50, Date().timeIntervalSince(lastFetch) < 60 {
            throw notOnRoute(sample)
        }
        guard usage.canSpend else {
            throw SpeedLimitProviderError.notConfigured("Månedens HERE-kvote er brugt. Bruger OpenStreetMap.")
        }

        lastFetch = Date()
        lastFetchCoordinate = sample.coordinate
        if drifting { driftRetryAfter = Date().addingTimeInterval(30) }
        do {
            var route = try await fetchRoute(for: sample, lookahead: lookahead)
            if route.points.count < 2 {
                // The point straight ahead may be unreachable (water, fields); try closer.
                route = try await fetchRoute(for: sample, lookahead: 300)
            }
            guard route.points.count >= 2 else {
                throw SpeedLimitProviderError.unavailable("HERE fandt ingen vej her")
            }
            path = route
            lastMatchIndex = 0
            driftCount = 0
        } catch {
            if let current { return try limit(from: current) }
            throw error
        }
        guard let hit = match(sample) else { throw notOnRoute(sample) }
        return try limit(from: hit)
    }

    private func fetchRoute(for sample: LocationSample, lookahead: Double) async throws -> HERERoutePath {
        guard usage.canSpend else {
            throw SpeedLimitProviderError.notConfigured("Månedens HERE-kvote er brugt. Bruger OpenStreetMap.")
        }
        guard Date() >= blockedUntil else {
            throw SpeedLimitProviderError.unavailable(
                "HERE afviste sidste forespørgsel. Prøver igen om \(Int(blockedUntil.timeIntervalSinceNow)) sek.")
        }
        usage.record()
        let (data, response) = try await session.data(for: makeRequest(for: sample, lookahead: lookahead))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if (400..<500).contains(status) { blockedUntil = Date().addingTimeInterval(60) }
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw SpeedLimitProviderError.unavailable("HERE svarede \(status): \(body)")
        }
        return try HERERoutePath(data: data)
    }

    private func notOnRoute(_ sample: LocationSample) -> Error {
        let distance = path?.nearestDistance(to: sample.coordinate).map { "\(Int($0)) m" } ?? "langt"
        return SpeedLimitProviderError.unavailable("Ikke på HERE's vej (nærmeste vej \(distance) væk)")
    }

    private func match(_ sample: LocationSample) -> HERERoutePath.Match? {
        guard let path, let hit = path.match(sample, near: lastMatchIndex) else { return nil }
        lastMatchIndex = hit.segment
        // Consistently off to the side: probably a parallel road or a ramp the route took.
        driftCount = hit.distance > driftDistance ? driftCount + 1 : 0
        return hit
    }

    private func limit(from match: HERERoutePath.Match) throws -> SpeedLimit {
        guard let mps = match.speedLimit else {
            throw SpeedLimitProviderError.unavailable("HERE kender ikke grænsen på \(match.roadName ?? "denne vej")")
        }
        return SpeedLimit(kmh: Int((mps * 3.6).rounded()), roadName: match.roadName, source: name)
    }

    func makeRequest(for sample: LocationSample, lookahead: Double) -> URLRequest {
        let hasCourse = sample.course >= 0 && sample.speed > 2
        let course = hasCourse ? sample.course : 0
        let destination = Self.offset(sample.coordinate, meters: lookahead, bearing: course)
        var origin = "\(sample.coordinate.latitude),\(sample.coordinate.longitude)"
        if hasCourse { origin += ";course=\(Int(course.rounded()) % 360)" }

        // Built by hand: URLQueryItem percent-encodes the "=" in ";course=", which HERE rejects.
        var keyCharacters = CharacterSet.alphanumerics
        keyCharacters.insert(charactersIn: "-_.~")
        let key = apiKey.addingPercentEncoding(withAllowedCharacters: keyCharacters) ?? ""
        let query = [
            "transportMode=car",
            "origin=\(origin)",
            "destination=\(destination.latitude),\(destination.longitude)",
            "return=polyline",
            "spans=speedLimit,names",
            "apiKey=\(key)",
        ].joined(separator: "&")
        return URLRequest(url: URL(string: "https://router.hereapi.com/v8/routes?\(query)")!, timeoutInterval: 10)
    }

    static func offset(_ coordinate: CLLocationCoordinate2D, meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        let dLat = meters * cos(radians) / RoadGeometry.earthRadius
        let dLon = meters * sin(radians) / (RoadGeometry.earthRadius * cos(coordinate.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat * 180 / .pi,
                                      longitude: coordinate.longitude + dLon * 180 / .pi)
    }
}

/// A route from the HERE Routing API with the speed limit of every segment.
struct HERERoutePath {
    let points: [CLLocationCoordinate2D]
    /// Speed limit in m/s for segment i (points[i] → points[i+1]); nil when unknown.
    let segmentLimits: [Double?]
    let segmentNames: [String?]
    /// Distance from the start of the path to points[i].
    let cumulative: [Double]

    struct Match {
        let segment: Int
        let distance: Double
        let speedLimit: Double?
        let roadName: String?
        let remaining: Double
    }

    init(data: Data) throws {
        struct Response: Decodable {
            struct Route: Decodable { let sections: [Section] }
            struct Section: Decodable {
                let polyline: String
                let spans: [Span]?
            }
            struct Span: Decodable {
                struct Name: Decodable { let value: String }
                let offset: Int
                let names: [Name]?
                let speedLimit: Double?
            }
            let routes: [Route]
        }

        var points: [CLLocationCoordinate2D] = []
        var limits: [Double?] = []
        var names: [String?] = []
        let sections = try JSONDecoder().decode(Response.self, from: data).routes.first?.sections ?? []
        for section in sections {
            let sectionPoints = try FlexiblePolyline.decode(section.polyline)
            guard sectionPoints.count >= 2 else { continue }
            if !points.isEmpty {
                // Bridge the gap between sections with an unknown segment.
                limits.append(nil)
                names.append(nil)
            }
            let spans = (section.spans ?? []).sorted { $0.offset < $1.offset }
            for segment in 0..<(sectionPoints.count - 1) {
                let span = spans.last { $0.offset <= segment }
                limits.append(span?.speedLimit)
                names.append(span?.names?.first?.value)
            }
            points += sectionPoints
        }
        self.init(points: points, segmentLimits: limits, segmentNames: names)
    }

    init(points: [CLLocationCoordinate2D], segmentLimits: [Double?], segmentNames: [String?]) {
        self.points = points
        self.segmentLimits = segmentLimits
        self.segmentNames = segmentNames
        var cumulative = [0.0]
        for i in points.indices.dropFirst() {
            cumulative.append(cumulative[i - 1] + RoadGeometry.distance(points[i - 1], points[i]))
        }
        self.cumulative = cumulative
    }

    var length: Double { cumulative.last ?? 0 }

    func nearestDistance(to coordinate: CLLocationCoordinate2D) -> Double? {
        guard points.count >= 2 else { return nil }
        return (0..<(points.count - 1))
            .map { RoadGeometry.match(point: coordinate, a: points[$0], b: points[$0 + 1]).distance }
            .min()
    }

    /// Finds the segment the car is on. Searches forward from `near` so the
    /// match can't jump back to an earlier part of the route that passes close by.
    func match(_ sample: LocationSample, near index: Int, maxDistance: Double = 30) -> Match? {
        guard points.count >= 2 else { return nil }
        let allowed = max(maxDistance, min(sample.horizontalAccuracy, 50) + 10)
        let hasHeading = sample.course >= 0 && sample.speed > 2
        var best: (segment: Int, distance: Double)?

        for segment in max(0, index - 2)..<(points.count - 1) {
            let hit = RoadGeometry.match(point: sample.coordinate, a: points[segment], b: points[segment + 1])
            guard hit.distance <= allowed else { continue }
            if hasHeading, RoadGeometry.angleDifference(sample.course, hit.bearing) > 60 { continue }
            if best == nil || hit.distance < best!.distance {
                best = (segment, hit.distance)
            }
        }
        guard let best else { return nil }
        return Match(segment: best.segment,
                     distance: best.distance,
                     speedLimit: segmentLimits[best.segment],
                     roadName: segmentNames[best.segment],
                     remaining: length - cumulative[best.segment + 1])
    }
}

/// Counts HERE requests per calendar month so the free quota isn't exceeded.
final class HEREUsage {
    private let defaults: UserDefaults
    var monthlyLimit: Int

    init(defaults: UserDefaults = .standard, monthlyLimit: Int) {
        self.defaults = defaults
        self.monthlyLimit = monthlyLimit
    }

    private var key: String {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return "hereRequests-\(components.year ?? 0)-\(components.month ?? 0)"
    }

    var thisMonth: Int { defaults.integer(forKey: key) }
    var canSpend: Bool { thisMonth < monthlyLimit }
    func record() { defaults.set(thisMonth + 1, forKey: key) }
}
