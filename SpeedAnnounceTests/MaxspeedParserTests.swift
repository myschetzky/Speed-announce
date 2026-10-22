import XCTest
@testable import SpeedAnnounce

final class MaxspeedParserTests: XCTestCase {
    func testNumericValues() {
        XCTAssertEqual(MaxspeedParser.parse("50"), .kmh(50))
        XCTAssertEqual(MaxspeedParser.parse(" 80 "), .kmh(80))
        XCTAssertEqual(MaxspeedParser.parse("110 km/h"), .kmh(110))
        XCTAssertEqual(MaxspeedParser.parse("30 mph"), .kmh(48))
        XCTAssertEqual(MaxspeedParser.parse("50;30"), .kmh(50))
    }

    func testZonesAndSpecialValues() {
        XCTAssertEqual(MaxspeedParser.parse("DK:urban"), .kmh(50))
        XCTAssertEqual(MaxspeedParser.parse("DK:rural"), .kmh(80))
        XCTAssertEqual(MaxspeedParser.parse("DK:motorway"), .kmh(130))
        XCTAssertEqual(MaxspeedParser.parse("none"), .unlimited)
        XCTAssertEqual(MaxspeedParser.parse("DE:motorway"), .unlimited)
        XCTAssertEqual(MaxspeedParser.parse("signals"), .unknown)
        XCTAssertEqual(MaxspeedParser.parse(""), .unknown)
        XCTAssertEqual(MaxspeedParser.parse(nil), .unknown)
    }
}
