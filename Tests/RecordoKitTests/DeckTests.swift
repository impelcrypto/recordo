import XCTest
@testable import RecordoKit

final class DeckTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func asked(_ offset: TimeInterval = 0) -> Asked {
        Asked(at: now.addingTimeInterval(offset), project: "demo", via: .btw)
    }

    func testMergeCreatesCardAtBoxZeroDueNow() {
        var deck = Deck()
        let created = deck.merge(term: "Foo-Rate", definition: "手数料の割合", tags: ["finance"],
                                 distractors: ["a", "b", "c"], asked: asked(-60), now: now)
        XCTAssertTrue(created)
        XCTAssertEqual(deck.cards.count, 1)
        let card = deck.cards[0]
        XCTAssertEqual(card.key, "foo-rate")
        XCTAssertEqual(card.term, "Foo-Rate")
        XCTAssertEqual(card.box, 0)
        XCTAssertEqual(card.due, now)
        XCTAssertEqual(card.asked, [asked(-60)])
        XCTAssertEqual(card.reviews, [])
    }

    func testAskingTheSameTermAgainResetsInsteadOfDuplicating() {
        var deck = Deck()
        deck.merge(term: "foo-rate", definition: "最初の定義", tags: ["finance"],
                   distractors: [], asked: asked(-86400), now: now.addingTimeInterval(-86400))
        deck.cards[0].box = 4
        let later = now.addingTimeInterval(3600)
        let created = deck.merge(term: "Foo-Rate とは？", definition: "別の定義", tags: ["other"],
                                 distractors: [], asked: asked(), now: later)
        XCTAssertFalse(created)
        XCTAssertEqual(deck.cards.count, 1)
        XCTAssertEqual(deck.cards[0].box, 0)
        XCTAssertEqual(deck.cards[0].due, later)
        XCTAssertEqual(deck.cards[0].asked.count, 2)
        XCTAssertEqual(deck.cards[0].definition, "最初の定義")
    }

    func testAnswerMovesTheBoxAndLogsTheReview() {
        var deck = Deck()
        deck.merge(term: "foo-rate", definition: "d", tags: [], distractors: [], asked: asked(), now: now)
        let id = deck.cards[0].id
        deck.answer(cardID: id, correct: true, now: now)
        XCTAssertEqual(deck.cards[0].box, 1)
        XCTAssertEqual(deck.cards[0].due, now.addingTimeInterval(4 * 3600))
        deck.answer(cardID: id, correct: false, now: now)
        XCTAssertEqual(deck.cards[0].box, 0)
        XCTAssertEqual(deck.cards[0].reviews, [Review(at: now, correct: true), Review(at: now, correct: false)])
    }

    func testAllTagsIsUniqueAndSorted() {
        var deck = Deck()
        deck.merge(term: "a", definition: "d", tags: ["web", "finance"], distractors: [], asked: asked(), now: now)
        deck.merge(term: "b", definition: "d", tags: ["web"], distractors: [], asked: asked(), now: now)
        XCTAssertEqual(deck.allTags, ["finance", "web"])
    }
}
