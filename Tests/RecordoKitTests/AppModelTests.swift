import XCTest
@testable import RecordoKit

extension XCTestCase {
    // The shared xctest defaults domain can hold another app's appLanguage; the argument domain outranks it.
    func useLanguage(_ language: AppLanguage) {
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[SettingsKey.language] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    override func setUp() {
        useLanguage(.japanese)
    }

    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func card(due: Date) -> Card {
        Card(id: UUID(), term: "foo", key: "foo", definition: "d", tags: [], distractors: ["x"], box: 1, due: due,
             asked: [], reviews: [])
    }

    func testNoticeSaysWhyNothingCanBeAsked() {
        let now = date(23, 19, 42)
        XCTAssertEqual(AppModel.notice(for: Deck(), now: now), .noCards)
        var deck = Deck()
        deck.cards = [card(due: date(23, 21, 40)), card(due: date(23, 21, 40)), card(due: date(24, 9))]
        XCTAssertEqual(AppModel.notice(for: deck, now: now), .nothingDue(next: date(23, 21, 40), count: 2))
    }

    func testNoticeCopyMatchesThePrototype() {
        let now = date(23, 19, 42)
        XCTAssertEqual(AppModel.noticeCopy(.noCards, now: now, calendar: calendar).title, "まだカードがありません")
        let due = AppModel.noticeCopy(.nothingDue(next: date(23, 21, 40), count: 2), now: now, calendar: calendar)
        XCTAssertEqual(due.title, "今出せるカードはありません")
        XCTAssertEqual(due.message, "次は今日 21:40 に 2 枚出ます。")
        XCTAssertEqual(AppModel.noticeCopy(.nothingDue(next: date(24, 9), count: 1), now: now, calendar: calendar).message,
                       "次は明日 9:00 に 1 枚出ます。")
        XCTAssertEqual(AppModel.noticeCopy(.unreadable, now: now, calendar: calendar).message,
                       "ファイルを直すまで、取り込みと出題を止めています。")
    }

    func testErrorsBecomeOneLineInstructions() {
        XCTAssertEqual(AppModel.message(for: ClaudeError.notFound), "claude が見つかりません。設定で場所を指定してください")
        XCTAssertEqual(AppModel.message(for: ClaudeError.notLoggedIn), "claude にログインしてください")
        XCTAssertEqual(AppModel.message(for: ClaudeError.badResponse), "claude の応答を読めませんでした")
        XCTAssertEqual(AppModel.message(for: CardStoreError.unreadable(URL(fileURLWithPath: "/tmp/x"), ClaudeError.badResponse)),
                       "cards.json を読めませんでした")
    }

    func testEnglishCopyFollowsTheLanguageSetting() {
        useLanguage(.english)
        let now = date(23, 19, 42)
        XCTAssertEqual(AppModel.noticeCopy(.nothingDue(next: date(23, 21, 40), count: 2), now: now, calendar: calendar).message,
                       "The next 2 cards are due today at 21:40.")
        XCTAssertEqual(AppModel.noticeCopy(.nothingDue(next: date(24, 9), count: 1), now: now, calendar: calendar).message,
                       "The next card is due tomorrow at 9:00.")
        XCTAssertEqual(AppModel.message(for: ClaudeError.notLoggedIn), "Log in to claude")
        XCTAssertEqual(QuizSession.meta(card(due: now)), "Uncategorized · Box 1")
    }

    func testSyncPercentCountsFinishedChunks() {
        XCTAssertEqual(AppModel.syncPercent(done: 0, total: 0), 0)
        XCTAssertEqual(AppModel.syncPercent(done: 1, total: 15), 0)
        XCTAssertEqual(AppModel.syncPercent(done: 7, total: 15), 40)
        XCTAssertEqual(AppModel.syncPercent(done: 15, total: 15), 93)
    }

    func testLastSyncText() {
        let now = date(23, 19, 42)
        XCTAssertEqual(AppModel.lastSyncText(nil, now: now, calendar: calendar), "まだ同期していません")
        XCTAssertEqual(AppModel.lastSyncText(date(23, 19, 4), now: now, calendar: calendar), "今日 19:04")
        XCTAssertEqual(AppModel.lastSyncText(date(20, 8, 5), now: now, calendar: calendar), "9/20 8:05")
    }
}
