import XCTest
@testable import RecordoKit

final class FakeClaudeRunner: ClaudeRunning {
    var responses: [String]
    var prompts: [String] = []
    var failOnCall: Int?

    init(_ responses: [String]) { self.responses = responses }

    func run(prompt: String, schema: String) async throws -> Data {
        prompts.append(prompt)
        if failOnCall == prompts.count { throw ClaudeError.failed("boom") }
        return Data(responses.removeFirst().utf8)
    }
}

final class ImporterTests: XCTestCase {
    var dir: URL!
    // 2026-09-23T10:40:00Z
    let now = Date(timeIntervalSince1970: 1_790_160_000)
    var nowMs: Int { Int(now.timeIntervalSince1970 * 1000) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("projects/-tmp-demo"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var store: CardStore { CardStore(url: dir.appendingPathComponent("cards.json")) }

    func writeHistory(_ rows: [(String, Int)]) throws {
        let lines = rows.map { display, ms -> String in
            let object: [String: Any] = ["display": display, "pastedContents": [String: String](), "timestamp": ms,
                                         "project": "/tmp/demo", "sessionId": "s1"]
            return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)
    }

    func writeTranscript(_ lines: [String]) throws {
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("projects/-tmp-demo/s1.jsonl"),
                                                atomically: true, encoding: .utf8)
    }

    func importer(_ runner: FakeClaudeRunner, chunkSize: Int = 200) -> Importer {
        Importer(store: store, runner: runner, historyURL: dir.appendingPathComponent("history.jsonl"),
                 projectsDir: dir.appendingPathComponent("projects"), chunkSize: chunkSize, batchSize: 10,
                 now: { self.now })
    }

    let classifyFoo = #"{"items":[{"id":0,"term":"foo-rate"}]}"#
    let generateFoo = #"{"cards":[{"id":0,"skip":false,"term":"foo-rate","definition":"手数料の割合","tags":["finance"],"distractors":["a","b","c"]}]}"#

    func testSyncCreatesACardFromTheConversationAndAdvancesTheCursor() async throws {
        let asked = nowMs - 3_600_000
        try writeHistory([("/btw foo-rate とは？", asked), ("please fix the build", asked + 1000)])
        try writeTranscript([
            #"{"type":"assistant","timestamp":"2026-09-23T09:39:00.000Z","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"foo-rate は 0.5 です。"}]}}"#,
        ])
        let runner = FakeClaudeRunner([classifyFoo, generateFoo])

        let changed = try await importer(runner).sync()

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(runner.prompts.count, 2)
        XCTAssertTrue(runner.prompts[0].contains("0: foo-rate とは？"))
        XCTAssertTrue(runner.prompts[0].contains("1: please fix the build"))
        XCTAssertTrue(runner.prompts[1].contains("foo-rate は 0.5 です。"))
        let deck = try store.load()
        XCTAssertEqual(deck.cards.map(\.key), ["foo-rate"])
        XCTAssertEqual(deck.cards[0].asked, [Asked(at: Date(timeIntervalSince1970: Double(asked) / 1000),
                                                   project: "demo", via: .btw)])
        XCTAssertEqual(deck.importedThrough, asked + 1000)
        XCTAssertEqual(deck.lastSyncAt, now)
    }

    func testEachTermOfATwoTermQuestionIsNamedInTheCardPrompt() async throws {
        try writeHistory([("foo-rate と bar-cache って何?", nowMs - 1000)])
        let classifyTwo = #"{"items":[{"id":0,"term":"foo-rate"},{"id":0,"term":"bar-cache"}]}"#
        let runner = FakeClaudeRunner([classifyTwo, #"{"cards":[]}"#])

        _ = try await importer(runner).sync()

        XCTAssertTrue(runner.prompts[1].contains("聞かれている用語: foo-rate"))
        XCTAssertTrue(runner.prompts[1].contains("聞かれている用語: bar-cache"))
    }

    func testAFailedCallSavesNothing() async throws {
        try writeHistory([("/btw foo-rate とは？", nowMs - 1000)])
        let runner = FakeClaudeRunner([classifyFoo, generateFoo])
        runner.failOnCall = 2
        do {
            _ = try await importer(runner).sync()
            XCTFail("expected the sync to fail")
        } catch {
            XCTAssertEqual(error as? ClaudeError, .failed("boom"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testAskingAgainResetsTheExistingCard() async throws {
        var deck = Deck()
        deck.merge(term: "foo-rate", definition: "最初の定義", tags: ["finance"], distractors: [],
                   asked: Asked(at: now.addingTimeInterval(-86400 * 3), project: "demo", via: .term),
                   now: now.addingTimeInterval(-86400 * 3))
        deck.cards[0].box = 4
        try store.save(deck)
        try writeHistory([("/btw foo-rate って何?", nowMs - 1000)])

        _ = try await importer(FakeClaudeRunner([classifyFoo, generateFoo])).sync()

        let saved = try store.load()
        XCTAssertEqual(saved.cards.count, 1)
        XCTAssertEqual(saved.cards[0].box, 0)
        XCTAssertEqual(saved.cards[0].due, now)
        XCTAssertEqual(saved.cards[0].asked.count, 2)
        XCTAssertEqual(saved.cards[0].definition, "最初の定義")
    }

    func testCardsAreWrittenInTheAppLanguage() async throws {
        try writeHistory([("/term bar-cache", nowMs - 1000)])
        useLanguage(.english)
        let english = FakeClaudeRunner([#"{"cards":[]}"#])
        _ = try await importer(english).sync()
        // The first sync moved the cursor past the question, so start the second from an empty deck.
        try FileManager.default.removeItem(at: store.url)
        useLanguage(.japanese)
        let japanese = FakeClaudeRunner([#"{"cards":[]}"#])
        _ = try await importer(japanese).sync()

        XCTAssertTrue(english.prompts[0].contains("英語で90字以内"))
        XCTAssertTrue(english.prompts[0].contains("差を15字以内"))
        XCTAssertTrue(japanese.prompts[0].contains("日本語で60字以内"))
        XCTAssertTrue(japanese.prompts[0].contains("差を10字以内"))
    }

    func testTermCommandsSkipTheJudgement() async throws {
        try writeHistory([("/term bar-cache", nowMs - 1000)])
        let generate = #"{"cards":[{"id":0,"skip":false,"term":"bar-cache","definition":"一時保存の層","tags":["web"],"distractors":["a","b","c"]}]}"#
        let runner = FakeClaudeRunner([generate])

        _ = try await importer(runner).sync()

        XCTAssertEqual(runner.prompts.count, 1)
        XCTAssertTrue(runner.prompts[0].contains("質問: bar-cache"))
        XCTAssertEqual(try store.load().cards.first?.asked.first?.via, .term)
    }

    func testQuestionsOlderThanThirtyDaysAreIgnored() async throws {
        try writeHistory([("/term old-term", nowMs - 31 * 86_400_000)])
        let runner = FakeClaudeRunner([])

        let changed = try await importer(runner).sync()

        XCTAssertEqual(changed, 0)
        XCTAssertTrue(runner.prompts.isEmpty)
        XCTAssertEqual(try store.load().lastSyncAt, now)
    }

    func testSkippedCardsAreNotCreatedButTheCursorMoves() async throws {
        try writeHistory([("/term baz", nowMs - 1000)])
        let runner = FakeClaudeRunner([#"{"cards":[{"id":0,"skip":true}]}"#])

        _ = try await importer(runner).sync()

        let deck = try store.load()
        XCTAssertTrue(deck.cards.isEmpty)
        XCTAssertEqual(deck.importedThrough, nowMs - 1000)
    }

    func testWorksInChunksAndReportsProgress() async throws {
        try writeHistory([("/term foo-rate", nowMs - 2000), ("/term bar-cache", nowMs - 1000)])
        let one = #"{"cards":[{"id":0,"skip":false,"term":"foo-rate","definition":"d","tags":[],"distractors":[]}]}"#
        let two = #"{"cards":[{"id":0,"skip":false,"term":"bar-cache","definition":"d","tags":[],"distractors":[]}]}"#
        let runner = FakeClaudeRunner([one, two])
        var steps: [[Int]] = []

        _ = try await importer(runner, chunkSize: 1).sync { steps.append([$0, $1]) }

        XCTAssertEqual(steps, [[1, 2], [2, 2]])
        XCTAssertEqual(try store.load().cards.map(\.key), ["foo-rate", "bar-cache"])
    }

    func testAnUnreadableStoreStopsBeforeAnyWork() async throws {
        try Data("{not json".utf8).write(to: store.url)
        try writeHistory([("/term foo-rate", nowMs - 1000)])
        let runner = FakeClaudeRunner([])
        do {
            _ = try await importer(runner).sync()
            XCTFail("expected the sync to fail")
        } catch {
            guard case CardStoreError.unreadable = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(runner.prompts.isEmpty)
        XCTAssertEqual(try String(contentsOf: store.url, encoding: .utf8), "{not json")
    }
}
