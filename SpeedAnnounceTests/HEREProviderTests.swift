import CoreLocation
import XCTest
@testable import SpeedAnnounce

final class HEREProviderTests: XCTestCase {
    /// Real HERE Routing v8 response (Rådhuspladsen → H. C. Andersens Boulevard, Copenhagen).
    private let response = """
    {"routes":[{"id":"4be9a291","sections":[{"id":"ea6fc1a8","type":"vehicle",
    "polyline":"BGmlmmqDmxi_XuG5Ekc7kB4IzKssBvvBwlB_nBwH7GwH7G8QnQwHjIjDnG3D7G7GkI3wB41BjSsTriBgjBrJgK_J0K7VsY7G4InG8LzFgP3NwW3N0ZvH4N7B4D7aw0BrJkSvHsO7GsOrO4cjSkmB_O8fvC0FvMkNjI0K3NsY3DoGjNsdvHwCvCkD_Y4wB3HqP",
    "spans":[
    {"offset":0,"names":[{"value":"Rådhuspladsen","language":"da"},{"value":"H. C. Andersens Boulevard","language":"da"}],"length":74,"speedLimit":13.8888893},
    {"offset":2,"names":[{"value":"H. C. Andersens Boulevard","language":"da"}],"length":552,"speedLimit":13.8888893},
    {"offset":17,"names":[{"value":"Rådhuspladsen","language":"da"}],"length":61,"speedLimit":13.8888893},
    {"offset":19,"names":[{"value":"H. C. Andersens Boulevard","language":"da"}],"length":126,"speedLimit":13.8888893},
    {"offset":25,"names":[{"value":"H. C. Andersens Boulevard","language":"da"}],"length":273},
    {"offset":33,"names":[{"value":"Dantes Plads","language":"da"}],"length":126,"speedLimit":13.8888893},
    {"offset":38,"names":[{"value":"H. C. Andersens Boulevard","language":"da"}],"length":106,"speedLimit":13.8888893}],
    "transport":{"mode":"car"}}]}]}
    """

    func testFlexiblePolylineDecoding() throws {
        let points = try FlexiblePolyline.decode("BGmlmmqDmxi_XuG5Ekc7kB4IzKssBvvBwlB_nBwH7GwH7G8QnQwHjIjDnG3D7G7GkI3wB41BjSsTriBgjBrJgK_J0K7VsY7G4InG8LzFgP3NwW3N0ZvH4N7B4D7aw0BrJkSvHsO7GsOrO4cjSkmB_O8fvC0FvMkNjI0K3NsY3DoGjNsdvHwCvCkD_Y4wB3HqP")
        XCTAssertEqual(points.count, 43)
        XCTAssertEqual(points[0].latitude, 55.675987, accuracy: 1e-6)
        XCTAssertEqual(points[0].longitude, 12.567827, accuracy: 1e-6)
        XCTAssertEqual(points[42].latitude, 55.672116, accuracy: 1e-6)
        XCTAssertEqual(points[42].longitude, 12.574685, accuracy: 1e-6)
    }

    func testRejectsInvalidPolyline() {
        XCTAssertThrowsError(try FlexiblePolyline.decode("B!"))
    }

    func testDecodesRouteWithSegmentLimits() throws {
        let path = try HERERoutePath(data: Data(response.utf8))
        XCTAssertEqual(path.points.count, 43)
        XCTAssertEqual(path.segmentLimits.count, 42)
        XCTAssertEqual(path.segmentNames[0], "Rådhuspladsen")
        XCTAssertEqual(path.segmentNames[2], "H. C. Andersens Boulevard")
        XCTAssertEqual(path.segmentLimits[10] ?? 0, 13.8888893, accuracy: 1e-6)
        XCTAssertNil(path.segmentLimits[30], "span at offset 25 has no speedLimit")
        XCTAssertEqual(path.length, 1_318, accuracy: 60)
    }

    func testMatchesCarDrivingAlongRoute() throws {
        let path = try HERERoutePath(data: Data(response.utf8))
        // Segment 35 is on the straight stretch south-east, far from the start where the route turns around.
        let a = path.points[35], b = path.points[36]
        let middle = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
        let bearing = RoadGeometry.match(point: middle, a: a, b: b).bearing

        let forward = LocationSample(coordinate: middle, course: bearing, speed: 12)
        let hit = try XCTUnwrap(path.match(forward, near: 0))
        XCTAssertEqual(hit.segment, 35)
        XCTAssertEqual(Int(((hit.speedLimit ?? 0) * 3.6).rounded()), 50)
        XCTAssertGreaterThan(hit.remaining, 0)

        let opposite = LocationSample(coordinate: middle, course: (bearing + 180).truncatingRemainder(dividingBy: 360), speed: 12)
        XCTAssertNil(path.match(opposite, near: 0), "driving the other way is a different route")

        let farAway = LocationSample(coordinate: HERESpeedLimitProvider.offset(middle, meters: 200, bearing: bearing + 90))
        XCTAssertNil(path.match(farAway, near: 0))
    }

    func testOffsetProjection() {
        let start = CLLocationCoordinate2D(latitude: 55.68, longitude: 12.57)
        let north = HERESpeedLimitProvider.offset(start, meters: 1_000, bearing: 0)
        XCTAssertEqual(RoadGeometry.distance(start, north), 1_000, accuracy: 1)
        XCTAssertGreaterThan(north.latitude, start.latitude)
        let east = HERESpeedLimitProvider.offset(start, meters: 1_000, bearing: 90)
        XCTAssertEqual(RoadGeometry.distance(start, east), 1_000, accuracy: 1)
        XCTAssertGreaterThan(east.longitude, start.longitude)
    }

    func testUsageCounterStopsAtLimit() {
        let defaults = UserDefaults(suiteName: "HEREUsageTests")!
        defaults.removePersistentDomain(forName: "HEREUsageTests")
        let usage = HEREUsage(defaults: defaults, monthlyLimit: 2)
        XCTAssertTrue(usage.canSpend)
        usage.record()
        usage.record()
        XCTAssertEqual(usage.thisMonth, 2)
        XCTAssertFalse(usage.canSpend)
    }
}
