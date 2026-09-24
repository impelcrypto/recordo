import XCTest
@testable import RecordoKit

final class LeitnerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testCorrectAnswerFollowsTheSpecTable() {
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400
        let table: [(box: Int, nextBox: Int, wait: TimeInterval)] = [
            (0, 1, 4 * hour), (1, 2, day), (2, 3, 3 * day),
            (3, 4, 7 * day), (4, 5, 14 * day), (5, 6, 30 * day), (6, 6, 30 * day),
        ]
        for row in table {
            let result = Leitner.next(box: row.box, correct: true, now: now)
            XCTAssertEqual(result.box, row.nextBox, "box \(row.box)")
            XCTAssertEqual(result.due, now.addingTimeInterval(row.wait), "box \(row.box)")
        }
    }

    func testWrongAnswerGoesBackToBoxZeroDueNow() {
        for box in 0...Leitner.maxBox {
            let result = Leitner.next(box: box, correct: false, now: now)
            XCTAssertEqual(result.box, 0)
            XCTAssertEqual(result.due, now)
        }
    }
}
