import XCTest
@testable import RecordoKit

@MainActor
final class QuizSessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        useLanguage(.japanese)
    }

    func card(_ term: String, due offset: TimeInterval, tags: [String] = ["finance"], box: Int = 2) -> Card {
        Card(id: UUID(), term: term, key: TermKey.normalize(term), definition: "\(term) の定義", tags: tags,
             distractors: ["誤り1", "誤り2", "誤り3"], box: box, due: now.addingTimeInterval(offset),
             asked: [Asked(at: Date(timeIntervalSince1970: 1_789_900_000), project: "demo", via: .btw)], reviews: [])
    }

    func deck(_ cards: [Card]) -> Deck {
        var deck = Deck()
        deck.cards = cards
        return deck
    }

    func testQuestionsAreTheOldestDueCardsUpToThree() {
        let cards = [card("a", due: -10), card("b", due: -30), card("c", due: 60), card("d", due: -20), card("e", due: -5)]
        let questions = QuizSession.questions(from: deck(cards), now: now, limit: 3)
        XCTAssertEqual(questions.map(\.term), ["b", "d", "a"])
    }

    func testLimitCapsTheQuestionCount() {
        let cards = (0..<12).map { card("t\($0)", due: -Double($0 + 1)) }
        XCTAssertEqual(QuizSession.questions(from: deck(cards), now: now, limit: 10).count, 10)
    }

    func testEachQuestionHasOneCorrectOptionThatIsTheDefinition() {
        let questions = QuizSession.questions(from: deck([card("foo-rate", due: -1)]), now: now, limit: 3)
        let options = questions[0].options
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(options.filter(\.isCorrect).map(\.text), ["foo-rate の定義"])
        XCTAssertEqual(options[questions[0].correctIndex].text, "foo-rate の定義")
    }

    func testCardsWithoutAnyWrongOptionAreSkipped() {
        var lonely = card("lonely", due: -1)
        lonely.distractors = []
        lonely.tags = ["nobody-else"]
        XCTAssertTrue(QuizSession.questions(from: deck([lonely]), now: now, limit: 3).isEmpty)
    }

    func testMetaAndSourceLines() {
        let c = card("foo-rate", due: -1, tags: ["トレーディング"], box: 2)
        XCTAssertEqual(QuizSession.meta(c), "トレーディング · 段 2")
        XCTAssertTrue(QuizSession.source(c.asked.last).hasSuffix("· demo · /btw で質問"))
        XCTAssertEqual(QuizSession.source(nil), "")
    }

    func testPickRecordsOnceAndLocksTheQuestion() {
        var answers: [(UUID, Bool)] = []
        let question = QuizQuestion(cardID: UUID(), term: "foo", meta: "", source: "",
                                    options: [QuizOption(text: "x", isCorrect: false), QuizOption(text: "y", isCorrect: true)])
        let session = QuizSession(questions: [question], onAnswer: { answers.append(($0, $1)) }, onDiscard: { _ in })
        session.pick(0)
        session.pick(1)
        XCTAssertEqual(session.verdict, .wrong)
        XCTAssertEqual(session.picked, 0)
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(answers.first?.1, false)
    }

    func testDontKnowCountsAsWrong() {
        var answers: [Bool] = []
        let session = QuizSession(questions: QuizSession.questions(from: deck([card("foo", due: -1)]), now: now, limit: 3),
                                  onAnswer: { answers.append($1) }, onDiscard: { _ in })
        session.dontKnow()
        XCTAssertEqual(session.verdict, .dontKnow)
        XCTAssertNil(session.picked)
        XCTAssertEqual(answers, [false])
    }

    func testDiscardIsAppliedOnlyWhenMovingOnAndUndoCancelsIt() {
        var removed: [UUID] = []
        let cards = [card("a", due: -2), card("b", due: -1)]
        let session = QuizSession(questions: QuizSession.questions(from: deck(cards), now: now, limit: 3),
                                  onAnswer: { _, _ in }, onDiscard: { removed.append($0) })
        session.discard()
        XCTAssertFalse(session.discarded, "discard before answering does nothing")
        session.pick(0)
        session.discard()
        session.undo()
        XCTAssertTrue(session.advance())
        XCTAssertTrue(removed.isEmpty)

        session.pick(0)
        session.discard()
        XCTAssertTrue(removed.isEmpty, "undo must stay possible until the person moves on")
        XCTAssertFalse(session.advance(), "the second question was the last")
        XCTAssertEqual(removed, [cards[1].id])
    }

    func testAdvanceResetsTheAnswerAndFinishAppliesAPendingDiscard() {
        var removed: [UUID] = []
        let cards = [card("a", due: -2), card("b", due: -1)]
        let session = QuizSession(questions: QuizSession.questions(from: deck(cards), now: now, limit: 3),
                                  onAnswer: { _, _ in }, onDiscard: { removed.append($0) })
        session.pick(1)
        session.advance()
        XCTAssertEqual(session.index, 1)
        XCTAssertNil(session.verdict)
        XCTAssertTrue(session.isLast)
        session.dontKnow()
        session.discard()
        session.finish()
        XCTAssertEqual(removed, [cards[1].id])
    }

    func testDeckRemove() {
        var d = deck([card("a", due: 0), card("b", due: 0)])
        let id = d.cards[0].id
        d.remove(cardID: id)
        XCTAssertEqual(d.cards.map(\.term), ["b"])
    }
}
