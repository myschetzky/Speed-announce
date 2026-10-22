import XCTest
@testable import SpeedAnnounce

final class AnnouncementPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private func limit(_ kmh: Int?) -> SpeedLimit { SpeedLimit(kmh: kmh, roadName: nil, source: "test") }
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    func testAnnouncesAfterConfirmation() {
        var policy = AnnouncementPolicy()
        XCTAssertEqual(policy.observe(limit(50), at: at(0)), [])
        XCTAssertEqual(policy.observe(limit(50), at: at(1)), [.limitChanged(.kmh(50))])
        XCTAssertEqual(policy.observe(limit(50), at: at(2)), [])
    }

    func testIgnoresSingleGlitch() {
        var policy = AnnouncementPolicy()
        _ = policy.observe(limit(50), at: at(0))
        _ = policy.observe(limit(50), at: at(1))
        XCTAssertEqual(policy.observe(limit(80), at: at(2)), [])
        XCTAssertEqual(policy.observe(limit(50), at: at(3)), [])
        XCTAssertEqual(policy.observe(limit(80), at: at(4)), [])
        XCTAssertEqual(policy.observe(limit(80), at: at(5)), [.limitChanged(.kmh(80))])
    }

    func testUnknownKeepsLimitDuringGrace() {
        var policy = AnnouncementPolicy()
        _ = policy.observe(limit(50), at: at(0))
        _ = policy.observe(limit(50), at: at(1))
        XCTAssertEqual(policy.observe(nil, at: at(10)), [])
        XCTAssertEqual(policy.confirmed, .kmh(50))
        XCTAssertEqual(policy.observe(nil, at: at(30)), [.limitLost])
        XCTAssertNil(policy.confirmed)
    }

    func testPeriodicAnnouncement() {
        var config = AnnouncementPolicy.Config()
        config.periodicInterval = 60
        var policy = AnnouncementPolicy(config: config)
        _ = policy.observe(limit(80), at: at(0))
        _ = policy.observe(limit(80), at: at(1))
        XCTAssertEqual(policy.tick(speedKmh: 70, at: at(30)), [])
        XCTAssertEqual(policy.tick(speedKmh: 70, at: at(61)), [.periodic(.kmh(80))])
        XCTAssertEqual(policy.tick(speedKmh: 70, at: at(90)), [])
        XCTAssertEqual(policy.tick(speedKmh: 70, at: at(121)), [.periodic(.kmh(80))])
    }

    func testSpeedingWarningAndRepeat() {
        var policy = AnnouncementPolicy()
        _ = policy.observe(limit(50), at: at(0))
        _ = policy.observe(limit(50), at: at(1))
        // Within tolerance (3 km/h).
        XCTAssertEqual(policy.tick(speedKmh: 53, at: at(10)), [])
        XCTAssertEqual(policy.tick(speedKmh: 60, at: at(11)), [])
        XCTAssertEqual(policy.tick(speedKmh: 60, at: at(13)), [.speeding(limit: 50, speed: 60)])
        XCTAssertEqual(policy.tick(speedKmh: 61, at: at(20)), [])
        XCTAssertEqual(policy.tick(speedKmh: 61, at: at(33)), [.speeding(limit: 50, speed: 61)])
        // Slowing down resets; a new burst warns again after the delay.
        XCTAssertEqual(policy.tick(speedKmh: 45, at: at(34)), [])
        XCTAssertEqual(policy.tick(speedKmh: 60, at: at(35)), [])
        XCTAssertEqual(policy.tick(speedKmh: 60, at: at(37)), [.speeding(limit: 50, speed: 60)])
    }

    func testNoWarningRightAfterLimitDrops() {
        var policy = AnnouncementPolicy()
        _ = policy.observe(limit(80), at: at(0))
        _ = policy.observe(limit(80), at: at(1))
        _ = policy.observe(limit(50), at: at(10))
        _ = policy.observe(limit(50), at: at(11))
        XCTAssertEqual(policy.tick(speedKmh: 75, at: at(12)), [])
        XCTAssertEqual(policy.tick(speedKmh: 75, at: at(14)), [])
        XCTAssertEqual(policy.tick(speedKmh: 70, at: at(17)), [.speeding(limit: 50, speed: 70)])
    }

    func testUnlimitedNeverWarns() {
        var policy = AnnouncementPolicy()
        _ = policy.observe(limit(nil), at: at(0))
        XCTAssertEqual(policy.observe(limit(nil), at: at(1)), [.limitChanged(.unlimited)])
        XCTAssertEqual(policy.tick(speedKmh: 200, at: at(10)), [])
        XCTAssertEqual(policy.tick(speedKmh: 200, at: at(20)), [])
    }
}
