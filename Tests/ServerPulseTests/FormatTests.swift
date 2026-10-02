import XCTest
@testable import ServerPulse

final class FormatTests: XCTestCase {
    func testPercentDouble() {
        XCTAssertEqual(Format.percent(12.46), "12%")
        XCTAssertEqual(Format.percent(Double?.none), "–")
    }

    func testPercentInt() {
        XCTAssertEqual(Format.percent(71), "71%")
        XCTAssertEqual(Format.percent(Int?.none), "–")
    }

    func testGigabytes() {
        XCTAssertEqual(Format.gigabytes(usedMB: 2072, totalMB: 3819), "2.0/3.7 GB")
        XCTAssertEqual(Format.gigabytes(usedMB: nil, totalMB: 3819), "–")
    }

    func testAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Format.age(since: now, now: now), "0s ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-12), now: now), "12s ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-59), now: now), "59s ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-60), now: now), "1m ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-3_599), now: now), "59m ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-7_200), now: now), "2h ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-3 * 86_400), now: now), "3d ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(5), now: now), "0s ago") // clock skew
    }
}
