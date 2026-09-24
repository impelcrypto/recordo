import XCTest
@testable import RecordoKit

final class HistoryReaderTests: XCTestCase {
    func line(_ display: String, _ timestamp: Int, session: String = "s1") -> String {
        let object: [String: Any] = ["display": display, "pastedContents": [String: String](), "timestamp": timestamp,
                                     "project": "/tmp/demo", "sessionId": session]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func testKeepsOnlyNewQuestionsWorthJudging() {
        let text = [
            line("old とは？", 1000),
            line("/clear", 2001),
            line("/btw what is foo-rate?", 2002),
            line("/term bar-cache", 2003),
            line("baz とは？", 2004),
            "{broken",
            line(String(repeating: "x", count: 501), 2005),
            line("   ", 2006),
            line("/btw ", 2007),
            line("no session", 2008, session: ""),
        ].joined(separator: "\n")

        let entries = HistoryReader.entries(fromJSONL: text, after: 2000)

        XCTAssertEqual(entries.map(\.timestamp), [2002, 2003, 2004])
        XCTAssertEqual(entries.map(\.via), [.btw, .term, .prompt])
        XCTAssertEqual(entries.map(\.body), ["what is foo-rate?", "bar-cache", "baz とは？"])
        XCTAssertEqual(entries[0].projectName, "demo")
    }
}
