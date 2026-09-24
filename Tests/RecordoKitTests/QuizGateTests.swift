import XCTest
@testable import RecordoKit

final class QuizGateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let hour: TimeInterval = 3600

    func testSyncRunsDailyAndWaitsAnHourAfterAFailure() {
        XCTAssertTrue(QuizGate.needsSync(lastSyncAt: nil, lastFailureAt: nil, now: now))
        XCTAssertFalse(QuizGate.needsSync(lastSyncAt: now.addingTimeInterval(-23 * hour), lastFailureAt: nil, now: now))
        XCTAssertTrue(QuizGate.needsSync(lastSyncAt: now.addingTimeInterval(-24 * hour), lastFailureAt: nil, now: now))
        XCTAssertFalse(QuizGate.needsSync(lastSyncAt: nil, lastFailureAt: now.addingTimeInterval(-30 * 60), now: now))
        XCTAssertTrue(QuizGate.needsSync(lastSyncAt: nil, lastFailureAt: now.addingTimeInterval(-2 * hour), now: now))
    }

    func testAskingWaitsForTheInterval() {
        XCTAssertTrue(QuizGate.isTimeToAsk(lastShownAt: nil, interval: 3 * hour, now: now))
        XCTAssertFalse(QuizGate.isTimeToAsk(lastShownAt: now.addingTimeInterval(-2 * hour), interval: 3 * hour, now: now))
        XCTAssertTrue(QuizGate.isTimeToAsk(lastShownAt: now.addingTimeInterval(-3 * hour), interval: 3 * hour, now: now))
    }

    func testQuietHoursWrapPastMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int, _ m: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: h, minute: m))!
        }
        let start = 22 * 60, end = 9 * 60
        XCTAssertTrue(QuizGate.inQuietHours(at(23, 0), start: start, end: end, calendar: calendar))
        XCTAssertTrue(QuizGate.inQuietHours(at(8, 59), start: start, end: end, calendar: calendar))
        XCTAssertFalse(QuizGate.inQuietHours(at(9, 0), start: start, end: end, calendar: calendar))
        XCTAssertFalse(QuizGate.inQuietHours(at(21, 59), start: start, end: end, calendar: calendar))
        XCTAssertTrue(QuizGate.inQuietHours(at(13, 0), start: 12 * 60, end: 14 * 60, calendar: calendar))
        XCTAssertFalse(QuizGate.inQuietHours(at(13, 0), start: 600, end: 600, calendar: calendar))
    }

    func testFocusReadsTheAssertionRecords() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func file(_ json: String) throws -> URL {
            let url = dir.appendingPathComponent(UUID().uuidString + ".json")
            try Data(json.utf8).write(to: url)
            return url
        }
        XCTAssertTrue(QuizGate.focusActive(assertionsURL: try file(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{}}]}]}"#)))
        XCTAssertFalse(QuizGate.focusActive(assertionsURL: try file(#"{"data":[{"storeAssertionRecords":[]}]}"#)))
        XCTAssertFalse(QuizGate.focusActive(assertionsURL: try file(#"{"data":[{}]}"#)))
        XCTAssertFalse(QuizGate.focusActive(assertionsURL: try file("not json")))
        XCTAssertFalse(QuizGate.focusActive(assertionsURL: dir.appendingPathComponent("missing.json")))
    }
}
