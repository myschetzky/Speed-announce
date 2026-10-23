import XCTest
@testable import SpeedAnnounce

@MainActor
final class TripLogTests: XCTestCase {
    private func entry(_ kind: TripLogEntry.Kind, _ limit: Int? = nil, at seconds: Double = 0) -> TripLogEntry {
        TripLogEntry(date: Date(timeIntervalSince1970: seconds), kind: kind, limitKmh: limit, speedKmh: 42,
                     road: "Køgevej", source: "HERE", latitude: 55.6, longitude: 12.5)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("triplog-\(UUID().uuidString).json")
    }

    func testGroupsEntriesPerTripNewestFirst() {
        let log = TripLog(fileURL: tempURL())
        log.add(entry(.tripStart, at: 0))
        log.add(entry(.limitChanged, 50, at: 1))
        log.add(entry(.tripStart, at: 100))
        log.add(entry(.limitChanged, 80, at: 101))
        log.add(entry(.speeding, 80, at: 102))

        let trips = log.trips
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].count, 3)
        XCTAssertEqual(trips[0][1].limitKmh, 80)
        XCTAssertEqual(trips[1].count, 2)
    }

    func testPersistsAndClears() {
        let url = tempURL()
        let log = TripLog(fileURL: url)
        log.add(entry(.tripStart))
        log.add(entry(.limitChanged, 30))
        XCTAssertEqual(TripLog(fileURL: url).entries.count, 2)

        log.clear()
        XCTAssertTrue(TripLog(fileURL: url).entries.isEmpty)
    }

    func testTitlesAndExport() {
        XCTAssertEqual(entry(.limitChanged, 30).title, "Fartgrænse 30")
        XCTAssertEqual(entry(.limitChanged, nil).title, "Ingen fartgrænse")
        XCTAssertEqual(entry(.speeding, 50).title, "For hurtigt: 42 i 50")
        XCTAssertNotNil(entry(.limitChanged, 30).mapURL)

        let log = TripLog(fileURL: tempURL())
        log.add(entry(.limitChanged, 30))
        XCTAssertTrue(log.exportText.contains("Fartgrænse 30 | Køgevej | 42 km/t | HERE | 55.60000,12.50000"))
    }
}
