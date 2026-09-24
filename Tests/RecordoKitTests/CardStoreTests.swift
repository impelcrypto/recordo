import XCTest
@testable import RecordoKit

final class CardStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileLoadsAnEmptyDeck() throws {
        let store = CardStore(url: dir.appendingPathComponent("cards.json"))
        XCTAssertEqual(try store.load(), Deck())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = CardStore(url: dir.appendingPathComponent("nested/cards.json"))
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var deck = Deck()
        deck.importedThrough = 1_790_000_000_123
        deck.lastSyncAt = now
        deck.merge(term: "foo-rate", definition: "手数料の割合", tags: ["finance"], distractors: ["a", "b", "c"],
                   asked: Asked(at: now, project: "demo", via: .term), now: now)
        try store.save(deck)
        XCTAssertEqual(try store.load(), deck)
    }

    func testUnreadableFileThrowsAndIsLeftAlone() throws {
        let url = dir.appendingPathComponent("cards.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        XCTAssertThrowsError(try CardStore(url: url).load()) { error in
            guard case CardStoreError.unreadable = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{not json")
    }

    func testDevRunsUseASeparateFile() {
        XCTAssertEqual(CardStore.defaultURL(isDev: true).lastPathComponent, "dev-cards.json")
        XCTAssertEqual(CardStore.defaultURL(isDev: false).lastPathComponent, "cards.json")
        XCTAssertTrue(CardStore.defaultURL(isDev: false).path.hasSuffix("Library/Application Support/Recordo/cards.json"))
    }
}
