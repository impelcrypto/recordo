import XCTest
@testable import RecordoKit

@MainActor
final class CardListTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        useLanguage(.japanese)
    }

    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    func card(_ term: String, box: Int = 2, askedAgo: TimeInterval = 0, definition: String? = nil,
              due offset: TimeInterval = 3600) -> Card {
        Card(id: UUID(), term: term, key: TermKey.normalize(term), definition: definition ?? "\(term) の定義",
             tags: ["web"], distractors: [], box: box, due: now.addingTimeInterval(offset),
             asked: [Asked(at: now.addingTimeInterval(-askedAgo), project: "demo", via: .btw)], reviews: [])
    }

    func testOnlyTheLastBoxCountsAsLearned() {
        let cards = [card("a", box: 0), card("b", box: 5), card("c", box: Leitner.maxBox)]
        let sections = CardList.sections(cards, query: "")
        XCTAssertEqual(sections.learning.map(\.term), ["a", "b"])
        XCTAssertEqual(sections.learned.map(\.term), ["c"])
    }

    func testEachSectionListsTheMostRecentlyAskedFirst() {
        var askedAgain = card("again", askedAgo: 900)
        askedAgain.asked.append(Asked(at: now, project: "demo", via: .term))
        let cards = [card("old", askedAgo: 500), askedAgain, card("new", askedAgo: 100),
                     card("learned old", box: 6, askedAgo: 800), card("learned new", box: 6, askedAgo: 200)]
        let sections = CardList.sections(cards, query: "")
        XCTAssertEqual(sections.learning.map(\.term), ["again", "new", "old"])
        XCTAssertEqual(sections.learned.map(\.term), ["learned new", "learned old"])
    }

    func testSearchMatchesTermOrDefinitionIgnoringCase() {
        let cards = [card("LCP"), card("tail latency"), card("Nagle", definition: "Adds LATENCY to small writes"),
                     card("CRDT", box: 6)]
        XCTAssertEqual(CardList.sections(cards, query: "lcp").learning.map(\.term), ["LCP"])
        XCTAssertEqual(Set(CardList.sections(cards, query: " Latency ").learning.map(\.term)), ["tail latency", "Nagle"])
        XCTAssertTrue(CardList.sections(cards, query: "xyz").learned.isEmpty)
    }

    func testPagesCutBothSectionsAsOneListOfAHundred() {
        let learning = (0..<150).map { card("l\($0)") }
        let learned = (0..<90).map { card("d\($0)", box: 6) }
        let first = CardList.page(0, learning: learning, learned: learned)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.learning.count, 100)
        XCTAssertTrue(first.learned.isEmpty)
        let second = CardList.page(1, learning: learning, learned: learned)
        XCTAssertEqual(second.learning.map(\.term).first, "l100")
        XCTAssertEqual(second.learning.count, 50)
        XCTAssertEqual(second.learned.count, 50)
        let last = CardList.page(2, learning: learning, learned: learned)
        XCTAssertTrue(last.learning.isEmpty)
        XCTAssertEqual(last.learned.map(\.term).first, "d50")
        XCTAssertEqual(last.learned.count, 40)
    }

    func testAPageThatNoLongerExistsFallsBackToTheLastOne() {
        let learning = (0..<30).map { card("l\($0)") }
        let page = CardList.page(4, learning: learning, learned: [])
        XCTAssertEqual(page.index, 0)
        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(page.learning.count, 30)
        XCTAssertEqual(CardList.page(0, learning: [], learned: []).count, 1)
    }

    func testDueCardsSayDueNowAndOthersSayWhenTheyAreNext() {
        XCTAssertEqual(CardList.dueText(card("a", due: 0), now: now, calendar: calendar), "出題待ち")
        XCTAssertEqual(CardList.dueText(card("b", due: -60), now: now, calendar: calendar), "出題待ち")
        // 1_790_000_000 is 2026-09-21 23:13 in Tokyo, so a day later is tomorrow.
        XCTAssertEqual(CardList.dueText(card("c", due: 86400), now: now, calendar: calendar), "次の出題 明日 23:13")
    }
}
