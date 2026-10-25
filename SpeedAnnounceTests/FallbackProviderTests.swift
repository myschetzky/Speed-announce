import CoreLocation
import XCTest
@testable import SpeedAnnounce

final class FallbackProviderTests: XCTestCase {
    private final class Stub: SpeedLimitProvider {
        let name: String
        var results: [Result<Int?, Error>]
        init(_ name: String, _ results: [Result<Int?, Error>]) {
            self.name = name
            self.results = results
        }
        func speedLimit(for sample: LocationSample) async throws -> SpeedLimit? {
            let next = results.isEmpty ? .success(nil) : results.removeFirst()
            return try next.get().map { SpeedLimit(kmh: $0, roadName: nil, source: name) }
        }
    }

    private let sample = LocationSample(coordinate: CLLocationCoordinate2D(latitude: 55.68, longitude: 12.57))

    func testUsesFallbackWhenPrimaryNeverHadALimit() async throws {
        let provider = FallbackSpeedLimitProvider(primary: Stub("HERE", [.success(nil)]),
                                                  fallback: Stub("OSM", [.success(80)]))
        let limit = try await provider.speedLimit(for: sample)
        XCTAssertEqual(limit?.kmh, 80)
        XCTAssertEqual(limit?.source, "OSM")
    }

    func testShortPrimaryGapIsUnknownInsteadOfFallback() async throws {
        let failure = SpeedLimitProviderError.unavailable("ikke på ruten")
        let provider = FallbackSpeedLimitProvider(primary: Stub("HERE", [.success(60), .failure(failure)]),
                                                  fallback: Stub("OSM", [.success(80)]))
        let first = try await provider.speedLimit(for: sample)
        XCTAssertEqual(first?.kmh, 60)
        // HERE briefly loses the road: don't jump to OSM's 80.
        let second = try await provider.speedLimit(for: sample)
        XCTAssertNil(second)
        XCTAssertNotNil(provider.primaryError)
    }

    func testFallbackAfterPrimaryGrace() async throws {
        let provider = FallbackSpeedLimitProvider(primary: Stub("HERE", [.success(60), .success(nil)]),
                                                  fallback: Stub("OSM", [.success(80)]))
        provider.primaryGrace = 0
        _ = try await provider.speedLimit(for: sample)
        let limit = try await provider.speedLimit(for: sample)
        XCTAssertEqual(limit?.kmh, 80)
    }
}
