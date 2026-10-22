import CoreLocation
import XCTest
@testable import SpeedAnnounce

final class OSMRoadMatcherTests: XCTestCase {
    // Two parallel roads ~45 m apart running east–west, and one running north–south.
    private let origin = CLLocationCoordinate2D(latitude: 55.68, longitude: 12.57)

    private func offset(east: Double, north: Double) -> CLLocationCoordinate2D {
        let lat = origin.latitude + north / RoadGeometry.earthRadius * 180 / .pi
        let lon = origin.longitude + east / (RoadGeometry.earthRadius * cos(origin.latitude * .pi / 180)) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func road(_ id: Int64, from: (Double, Double), to: (Double, Double), tags: [String: String]) -> OSMRoad {
        OSMRoad(id: id, geometry: [offset(east: from.0, north: from.1), offset(east: to.0, north: to.1)], tags: tags)
    }

    func testPicksNearestRoad() {
        let roads = [
            road(1, from: (-200, 0), to: (200, 0), tags: ["maxspeed": "50"]),
            road(2, from: (-200, 45), to: (200, 45), tags: ["maxspeed": "80"]),
        ]
        let sample = LocationSample(coordinate: offset(east: 0, north: 8))
        let match = OSMRoadMatcher().bestMatch(for: sample, roads: roads, previousRoadId: nil)
        XCTAssertEqual(match?.road.id, 1)
    }

    func testHeadingPrefersAlignedRoadAtCrossing() {
        let roads = [
            road(1, from: (-200, 0), to: (200, 0), tags: ["maxspeed": "50"]),
            road(2, from: (5, -200), to: (5, 200), tags: ["maxspeed": "80"]),
        ]
        // Slightly closer to road 1, but driving north.
        let sample = LocationSample(coordinate: offset(east: 0, north: 3), course: 0, speed: 15)
        let match = OSMRoadMatcher().bestMatch(for: sample, roads: roads, previousRoadId: nil)
        XCTAssertEqual(match?.road.id, 2)
    }

    func testFarFromAnyRoadReturnsNil() {
        let roads = [road(1, from: (-200, 0), to: (200, 0), tags: ["maxspeed": "50"])]
        let sample = LocationSample(coordinate: offset(east: 0, north: 150))
        XCTAssertNil(OSMRoadMatcher().bestMatch(for: sample, roads: roads, previousRoadId: nil))
    }

    func testDirectionalMaxspeed() {
        let tags = ["maxspeed": "80", "maxspeed:forward": "60", "maxspeed:backward": "70"]
        let roads = [road(1, from: (-200, 0), to: (200, 0), tags: tags)]
        let east = LocationSample(coordinate: offset(east: 0, north: 2), course: 90, speed: 15)
        let west = LocationSample(coordinate: offset(east: 0, north: 2), course: 270, speed: 15)
        let matcher = OSMRoadMatcher()
        XCTAssertEqual(matcher.bestMatch(for: east, roads: roads, previousRoadId: nil).map(OSMRoadMatcher.maxspeed), .kmh(60))
        XCTAssertEqual(matcher.bestMatch(for: west, roads: roads, previousRoadId: nil).map(OSMRoadMatcher.maxspeed), .kmh(70))
    }

    func testDecodesOverpassResponse() throws {
        let json = """
        {"elements":[{"type":"way","id":7,"tags":{"highway":"primary","maxspeed":"60","name":"Vej"},
          "geometry":[{"lat":55.0,"lon":12.0},{"lat":55.001,"lon":12.0}]}]}
        """
        let roads = try OSMSpeedLimitProvider.decode(Data(json.utf8))
        XCTAssertEqual(roads.count, 1)
        XCTAssertEqual(roads.first?.name, "Vej")
        XCTAssertEqual(roads.first?.geometry.count, 2)
    }
}
