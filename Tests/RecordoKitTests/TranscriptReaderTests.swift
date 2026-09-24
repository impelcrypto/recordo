import XCTest
@testable import RecordoKit

final class TranscriptReaderTests: XCTestCase {
    // 2026-09-23T10:00:00.000Z in milliseconds.
    let ten = 1_790_157_600_000

    func row(_ type: String, _ time: String, source: String? = nil, sidechain: Bool = false, _ content: Any) -> String {
        var object: [String: Any] = ["type": type, "timestamp": time, "isSidechain": sidechain,
                                     "message": ["role": type, "content": content] as [String: Any]]
        if let source { object["promptSource"] = source }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func text(_ s: String) -> [[String: Any]] { [["type": "text", "text": s]] }

    lazy var transcript: String = [
        row("user", "2026-09-23T09:55:00.000Z", source: "typed", "foo-rate の設定を見て"),
        row("assistant", "2026-09-23T09:55:05.000Z", [["type": "thinking", "thinking": "..."],
                                                      ["type": "tool_use", "name": "Read"]]),
        row("user", "2026-09-23T09:55:06.000Z", [["type": "tool_result", "content": "SECRET TOOL OUTPUT"]]),
        row("assistant", "2026-09-23T09:55:25.000Z", text("foo-rate は 0.5 に設定されています。")),
        row("user", "2026-09-23T09:57:31.000Z", source: "typed", "ok"),
        row("assistant", "2026-09-23T09:57:37.000Z", text("了解です。")),
        row("user", "2026-09-23T10:10:00.200Z", source: "typed", "bar-cache とは？"),
        row("assistant", "2026-09-23T10:10:03.000Z", [["type": "thinking", "thinking": "..."]]),
        row("assistant", "2026-09-23T10:10:04.000Z", text("bar-cache は一時保存の層です。")),
        row("user", "2026-09-23T10:10:05.000Z", [["type": "tool_result", "content": "SECRET TOOL OUTPUT"]]),
        row("assistant", "2026-09-23T10:10:05.500Z", sidechain: true, text("SIDECHAIN TEXT")),
        row("assistant", "2026-09-23T10:10:06.000Z", text("期限は1時間です。")),
        row("user", "2026-09-23T10:11:00.000Z", source: "queued", "baz-flag とは？"),
        row("assistant", "2026-09-23T10:11:05.000Z", text("baz-flag は機能の切り替えです。")),
    ].joined(separator: "\n")

    func entry(_ display: String, at ms: Int) -> HistoryEntry {
        HistoryEntry(display: display, timestamp: ms, project: "/tmp/demo", sessionId: "s1")
    }

    func testTurnsKeepOnlyPeopleAndAssistantText() {
        let turns = TranscriptReader.turns(fromJSONL: transcript)
        XCTAssertEqual(turns.map(\.role), [.human, .assistant, .human, .assistant, .human, .assistant, .assistant, .human, .assistant])
        XCTAssertFalse(turns.contains { $0.text.contains("SECRET") || $0.text.contains("SIDECHAIN") })
        XCTAssertEqual(turns[0].time, ten - 5 * 60_000)
    }

    func testBtwUsesTheNearestEarlierTurnThatMentionsTheTerm() throws {
        let turns = TranscriptReader.turns(fromJSONL: transcript)
        let context = try XCTUnwrap(TranscriptReader.context(for: entry("/btw foo-rate とは？", at: ten),
                                                             term: "Foo-Rate", turns: turns))
        XCTAssertTrue(context.contains("foo-rate は 0.5 に設定されています。"))
        XCTAssertLessThanOrEqual(context.count, 6000)
    }

    func testBtwKeepsTheAnchorLineWhenTheTurnBeforeItIsVeryLong() throws {
        let lines = [
            row("user", "2026-09-23T09:00:00.000Z", source: "typed", String(repeating: "a", count: 6_500)),
            row("assistant", "2026-09-23T09:00:05.000Z", text("zap-rate は架空の値です。")),
            row("user", "2026-09-23T09:00:10.000Z", source: "typed", "ok"),
        ].joined(separator: "\n")
        let turns = TranscriptReader.turns(fromJSONL: lines)
        let context = try XCTUnwrap(TranscriptReader.context(for: entry("/btw zap-rate とは？", at: ten),
                                                             term: "zap-rate", turns: turns))
        XCTAssertTrue(context.contains("zap-rate は架空の値です。"))
        XCTAssertLessThanOrEqual(context.count, 6000)
    }

    func testBtwFallsBackToTheLastTurnsWhenTheTermNeverAppears() throws {
        let turns = TranscriptReader.turns(fromJSONL: transcript)
        let context = try XCTUnwrap(TranscriptReader.context(for: entry("/btw qux とは？", at: ten),
                                                             term: "qux", turns: turns))
        XCTAssertTrue(context.hasSuffix("[assistant] 了解です。"))
    }

    func testPromptUsesTheReplyThatFollowedIt() {
        let turns = TranscriptReader.turns(fromJSONL: transcript)
        let context = TranscriptReader.context(for: entry("bar-cache とは？", at: ten + 10 * 60_000),
                                               term: "bar-cache", turns: turns)
        XCTAssertEqual(context, "bar-cache は一時保存の層です。\n期限は1時間です。")
    }

    func testQueuedPromptsCountAsPeople() {
        let turns = TranscriptReader.turns(fromJSONL: transcript)
        let context = TranscriptReader.context(for: entry("/term baz-flag", at: ten + 11 * 60_000 - 300),
                                               term: "baz-flag", turns: turns)
        XCTAssertEqual(context, "baz-flag は機能の切り替えです。")
    }

    func testSlashCommandsCountAsPeopleButTheirSkillTextDoesNot() {
        let lines = [
            row("user", "2026-09-23T10:30:00.015Z",
                "<command-message>term</command-message>\n<command-name>/term</command-name>\n<command-args>qux-rate</command-args>"),
            row("user", "2026-09-23T10:30:00.015Z", text("Base directory for this skill: /tmp/term")),
            row("assistant", "2026-09-23T10:30:06.000Z", [["type": "thinking", "thinking": "..."]]),
            row("assistant", "2026-09-23T10:30:08.000Z", text("qux-rate は架空の率です。")),
        ].joined(separator: "\n")
        let turns = TranscriptReader.turns(fromJSONL: lines)
        XCTAssertEqual(turns.map(\.role), [.human, .assistant])
        XCTAssertEqual(TranscriptReader.context(for: entry("/term qux-rate", at: ten + 30 * 60_000),
                                                term: "qux-rate", turns: turns),
                       "qux-rate は架空の率です。")
    }

    func testPromptWithoutAPersonWithinFiveSecondsHasNoContext() {
        let turns = TranscriptReader.turns(fromJSONL: transcript)
        XCTAssertNil(TranscriptReader.context(for: entry("bar-cache とは？", at: ten + 10 * 60_000 - 6_000),
                                              term: "bar-cache", turns: turns))
    }

    func testFindsTheTranscriptInAnyProjectFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = dir.appendingPathComponent("-tmp-demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent("s1.jsonl"))
        XCTAssertEqual(TranscriptReader.url(sessionId: "s1", projectsDir: dir)?.lastPathComponent, "s1.jsonl")
        XCTAssertNil(TranscriptReader.url(sessionId: "missing", projectsDir: dir))
    }
}
