import CoreLocation

/// Speed limits from OpenStreetMap via the Overpass API.
///
/// Roads around the vehicle are fetched in one request and cached, so the
/// network is only hit when the vehicle approaches the edge of the cached area.
final class OSMSpeedLimitProvider: SpeedLimitProvider {
    let name = "OpenStreetMap"

    private let cache = RoadCache()
    private let matcher = OSMRoadMatcher()
    private let session: URLSession
    private let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
    ]
    /// Radius of each fetched area in metres.
    private let fetchRadius = 1_200.0
    /// Refetch when this close to the edge of the cached area.
    private let refetchMargin = 500.0

    init(session: URLSession = .shared) {
        self.session = session
    }

    func speedLimit(for sample: LocationSample) async throws -> SpeedLimit? {
        let roads = try await roads(around: sample.coordinate)
        let previous = await cache.previousRoadId
        guard let match = matcher.bestMatch(for: sample, roads: roads, previousRoadId: previous) else {
            await cache.setPreviousRoadId(nil)
            return nil
        }
        await cache.setPreviousRoadId(match.road.id)

        switch OSMRoadMatcher.maxspeed(for: match) {
        case .kmh(let value): return SpeedLimit(kmh: value, roadName: match.road.name, source: name)
        case .unlimited: return SpeedLimit(kmh: nil, roadName: match.road.name, source: name)
        case .unknown: return nil
        }
    }

    private func roads(around coordinate: CLLocationCoordinate2D) async throws -> [OSMRoad] {
        if let cached = await cache.roads(near: coordinate, validWithin: fetchRadius - refetchMargin) {
            return cached
        }
        guard await cache.beginFetch() else {
            // Another fetch is running or we are backing off: use what we have.
            return await cache.allRoads
        }
        do {
            let roads = try await fetchRoads(around: coordinate)
            await cache.store(roads, center: coordinate)
            return roads
        } catch {
            await cache.fetchFailed()
            let fallback = await cache.allRoads
            if fallback.isEmpty { throw error }
            return fallback
        }
    }

    private func fetchRoads(around coordinate: CLLocationCoordinate2D) async throws -> [OSMRoad] {
        let highways = "motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|road"
        let query = """
        [out:json][timeout:20];
        way(around:\(Int(fetchRadius)),\(coordinate.latitude),\(coordinate.longitude))["highway"~"^(\(highways))$"];
        out tags geom;
        """
        var lastError: Error = SpeedLimitProviderError.badResponse(0)
        for endpoint in endpoints {
            var request = URLRequest(url: endpoint, timeoutInterval: 25)
            request.httpMethod = "POST"
            request.setValue("SpeedAnnounce-iOS/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            request.httpBody = Data("data=\(encoded)".utf8)
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw SpeedLimitProviderError.badResponse(status) }
                return try Self.decode(data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func decode(_ data: Data) throws -> [OSMRoad] {
        struct Response: Decodable {
            struct Element: Decodable {
                struct Point: Decodable { let lat: Double; let lon: Double }
                let type: String
                let id: Int64
                let tags: [String: String]?
                let geometry: [Point]?
            }
            let elements: [Element]
        }
        return try JSONDecoder().decode(Response.self, from: data).elements.compactMap { element in
            guard element.type == "way", let geometry = element.geometry else { return nil }
            return OSMRoad(
                id: element.id,
                geometry: geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                tags: element.tags ?? [:]
            )
        }
    }
}

private actor RoadCache {
    private(set) var allRoads: [OSMRoad] = []
    private(set) var previousRoadId: Int64?
    private var center: CLLocationCoordinate2D?
    private var isFetching = false
    private var retryAfter = Date.distantPast

    func roads(near coordinate: CLLocationCoordinate2D, validWithin radius: Double) -> [OSMRoad]? {
        guard let center, RoadGeometry.distance(center, coordinate) < radius else { return nil }
        return allRoads
    }

    func beginFetch() -> Bool {
        guard !isFetching, Date() >= retryAfter else { return false }
        isFetching = true
        return true
    }

    func store(_ roads: [OSMRoad], center: CLLocationCoordinate2D) {
        allRoads = roads
        self.center = center
        isFetching = false
    }

    func fetchFailed() {
        isFetching = false
        retryAfter = Date().addingTimeInterval(15)
    }

    func setPreviousRoadId(_ id: Int64?) { previousRoadId = id }
}
