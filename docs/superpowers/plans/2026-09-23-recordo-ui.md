# Recordo 計画2：画面（出題の小窓、メニュー、設定、.app）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 計画1の中身の上に、メニューバー常駐の Recordo アプリを作る。3時間おきに右下へ4択の小窓を出し、メニューから出題、同期、設定ができ、`make install` で `/Applications` に入る。

**Architecture:** ロジックはこれまでどおり `RecordoKit` に置く。画面を持たない部分（出題の流れ `QuizSession`、出すかどうかの判定 `QuizGate`、状態のまとめ役 `AppModel` の静的関数）を先に作ってテストし、その上に SwiftUI の画面（`QuizView`、`QuizNoticeView`、`SettingsView`、`MenuBarExtra`）と AppKit の小窓（`QuizPanel`）を載せる。見た目と動きは承認済みの HTML 試作（`design/sessions/quiz/`）に合わせる。

**Tech Stack:** Swift 6.4 ツールチェーン（言語モード Swift 5）、SwiftUI（`MenuBarExtra`、`Settings`）、AppKit（`NSPanel`、`NSVisualEffectView`）、XCTest。外部の依存パッケージなし。

**設計書:** `docs/superpowers/specs/2026-09-23-recordo-design.md`
**承認済みの試作:** `design/sessions/quiz/apple-quiz.html`、`apple-quiz-spec.md`
**計画1:** `docs/superpowers/plans/2026-09-23-recordo-core.md`（ここで作った型をそのまま使う）

## Global Constraints

- `git add`、`git commit`、`git push` は実行しない。コミットはユーザーが行う。各タスクの最後は `git status --short` で変更を確認し、`git diff --cached --stat` が空であることを確かめて区切りを報告する。
- `Package.swift` は変えない（依存パッケージを足さない、`.swiftLanguageMode(.v5)` のまま）。
- 画面に関わる型（`AppModel`、`QuizSession`、`QuizPanel`、各 View）は `@MainActor`。`claude -p` を呼ぶ `Importer.sync` はメインスレッドの外で動くので、進み具合の通知は `Task { @MainActor in … }` でメインに戻す。`DispatchQueue.main.async` を散らさない。
- 同期と出題は同時に動かさない。同期中は出題しない（自動も「今すぐ出題」も）、小窓を出している間は同期を始めない。`Importer` は同期の最初に読んだカードを塊ごとに保存するので、同期中に答えた結果は上書きされて消えるため。
- UI の文言は試作の仕様書（`apple-quiz-spec.md`）どおりの日本語。実装中に英語も求められたので、`tr("日本語", "English")` で並べ、設定で言語を選べるようにした（2026-09-23）。コードのコメントは英語で2行まで、理由だけを書く。
- テストのフィクスチャは架空の内容で作る（用語は `foo-rate`、`bar-cache` など）。
- `swift run` と `make dev` は `dev-cards.json`、`.app` は `cards.json` を使う（計画1の `CardStore.defaultURL()` のまま）。
- `public` は `RecordoKit` の外（`Sources/Recordo/main.swift`）から使うものだけ。計画2で増えるのは `RecordoMain.run(arguments:)` だけ。

## 検証の限界

`swift test` で確かめられるのは Task 1、2、3（出題の流れ、判定、文言とエラーの言い換え）まで。Task 4〜7（見た目、動き、メニュー、設定、`.app`）は、アプリを起動して画面を見て確かめる。集中モードと全画面での抑止は、実装する側では切り替えられないので、最後にユーザーに確かめてもらう。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `Sources/RecordoKit/Card.swift`（変更） | `Deck.remove(cardID:)` を足す |
| `Sources/RecordoKit/QuizSession.swift` | 出題する問題の組み立てと、1回の出題の流れ（答える、分からない、捨てる、元に戻す、次へ） |
| `Sources/RecordoKit/QuizGate.swift` | 出すかどうか、同期するかどうかの判定。静かな時間帯、集中モード、全画面 |
| `Sources/RecordoKit/AppModel.swift` | カード、同期の状態、小窓の表示をまとめる。60秒ごとのチェック |
| `Sources/RecordoKit/Theme.swift` | 色（ライトとダーク）とカーソル |
| `Sources/RecordoKit/QuizStyle.swift` | 文字サイズ、寸法、動き、小窓の枠、選択肢の行、ボタン |
| `Sources/RecordoKit/QuizPanel.swift` | 右下に出す `NSPanel`、大きさの調整、背景のぼかし |
| `Sources/RecordoKit/QuizView.swift` | 出題の画面 |
| `Sources/RecordoKit/QuizNoticeView.swift` | 出せるカードがないときの画面 |
| `Sources/RecordoKit/Settings.swift` | 設定のキーと設定ウィンドウ |
| `Sources/RecordoKit/RecordoApp.swift` | アプリの入口、`MenuBarExtra`、`--sync-once` |
| `Sources/Recordo/main.swift`（置き換え） | `RecordoMain.run(arguments:)` を呼ぶだけ |
| `scripts/bundle.sh` | `.app` を作る |
| `Makefile`（変更） | `dev`、`app`、`install` を足し、`sync` にアプリ起動中の確認を足す |
| `.gitignore`（変更） | `build.noindex/` |
| `Tests/RecordoKitTests/QuizSessionTests.swift` ほか | テスト |

---

### Task 1: カードの削除と出題の流れ

**Files:**
- Modify: `Sources/RecordoKit/Card.swift`（`Deck` に1メソッド）
- Create: `Sources/RecordoKit/QuizSession.swift`
- Test: `Tests/RecordoKitTests/QuizSessionTests.swift`

**Interfaces:**
- Consumes: `Deck`、`Card`、`Asked`、`Via`、`Deck.answer(cardID:correct:now:)`（計画1 Task 2）、`Distractors.pick(for:from:)`（計画1 Task 4）
- Produces:
  - `Deck.remove(cardID: UUID)`
  - `struct QuizOption: Equatable { let text: String; let isCorrect: Bool }`
  - `struct QuizQuestion: Equatable { let cardID: UUID; let term: String; let meta: String; let source: String; let options: [QuizOption]; var correctIndex: Int }`
  - `enum Verdict: Equatable { case correct, wrong, dontKnow }`
  - `@MainActor final class QuizSession: ObservableObject { let questions; index; verdict; picked; discarded; current; isLast; init(questions:onAnswer:onDiscard:); pick(_:); dontKnow(); discard(); undo(); advance() -> Bool; finish(); static func questions(from:now:limit:) -> [QuizQuestion]; static func meta(_:) -> String; static func source(_:) -> String }`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/QuizSessionTests.swift`:

```swift
import XCTest
@testable import RecordoKit

@MainActor
final class QuizSessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

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
        let questions = QuizSession.questions(from: deck(cards), now: now)
        XCTAssertEqual(questions.map(\.term), ["b", "d", "a"])
    }

    func testEachQuestionHasOneCorrectOptionThatIsTheDefinition() {
        let questions = QuizSession.questions(from: deck([card("foo-rate", due: -1)]), now: now)
        let options = questions[0].options
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(options.filter(\.isCorrect).map(\.text), ["foo-rate の定義"])
        XCTAssertEqual(options[questions[0].correctIndex].text, "foo-rate の定義")
    }

    func testCardsWithoutAnyWrongOptionAreSkipped() {
        var lonely = card("lonely", due: -1)
        lonely.distractors = []
        lonely.tags = ["nobody-else"]
        XCTAssertTrue(QuizSession.questions(from: deck([lonely]), now: now).isEmpty)
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
        let session = QuizSession(questions: QuizSession.questions(from: deck([card("foo", due: -1)]), now: now),
                                  onAnswer: { answers.append($1) }, onDiscard: { _ in })
        session.dontKnow()
        XCTAssertEqual(session.verdict, .dontKnow)
        XCTAssertNil(session.picked)
        XCTAssertEqual(answers, [false])
    }

    func testDiscardIsAppliedOnlyWhenMovingOnAndUndoCancelsIt() {
        var removed: [UUID] = []
        let cards = [card("a", due: -2), card("b", due: -1)]
        let session = QuizSession(questions: QuizSession.questions(from: deck(cards), now: now),
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
        let session = QuizSession(questions: QuizSession.questions(from: deck(cards), now: now),
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter QuizSessionTests`
Expected: コンパイルエラー `cannot find 'QuizSession' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/Card.swift` の `Deck` の `answer(cardID:correct:now:)` の後ろに足す:

```swift
    mutating func remove(cardID: UUID) {
        cards.removeAll { $0.id == cardID }
    }
```

`Sources/RecordoKit/QuizSession.swift`:

```swift
import Foundation

struct QuizOption: Equatable {
    let text: String
    let isCorrect: Bool
}

struct QuizQuestion: Equatable {
    let cardID: UUID
    let term: String
    let meta: String
    let source: String
    let options: [QuizOption]

    var correctIndex: Int { options.firstIndex(where: \.isCorrect) ?? 0 }
}

enum Verdict: Equatable {
    case correct, wrong, dontKnow
}

@MainActor
final class QuizSession: ObservableObject {
    let questions: [QuizQuestion]
    @Published private(set) var index = 0
    @Published private(set) var verdict: Verdict?
    @Published private(set) var picked: Int?
    @Published private(set) var discarded = false
    private let onAnswer: (UUID, Bool) -> Void
    private let onDiscard: (UUID) -> Void

    init(questions: [QuizQuestion], onAnswer: @escaping (UUID, Bool) -> Void, onDiscard: @escaping (UUID) -> Void) {
        self.questions = questions
        self.onAnswer = onAnswer
        self.onDiscard = onDiscard
    }

    var current: QuizQuestion { questions[index] }
    var isLast: Bool { index >= questions.count - 1 }

    func pick(_ option: Int) {
        guard verdict == nil, current.options.indices.contains(option) else { return }
        let correct = current.options[option].isCorrect
        picked = option
        verdict = correct ? .correct : .wrong
        onAnswer(current.cardID, correct)
    }

    // A lucky 1-in-4 guess would stretch the interval of a card that was not remembered.
    func dontKnow() {
        guard verdict == nil else { return }
        verdict = .dontKnow
        onAnswer(current.cardID, false)
    }

    func discard() {
        if verdict != nil { discarded = true }
    }

    func undo() {
        discarded = false
    }

    /// Moves to the next question and returns false when the last one is done.
    @discardableResult
    func advance() -> Bool {
        guard verdict != nil else { return true }
        applyDiscard()
        guard !isLast else { return false }
        index += 1
        verdict = nil
        picked = nil
        return true
    }

    func finish() {
        applyDiscard()
    }

    // Discarding waits until the person moves on, so 元に戻す works without re-inserting a card.
    private func applyDiscard() {
        guard discarded else { return }
        discarded = false
        onDiscard(current.cardID)
    }

    static func questions(from deck: Deck, now: Date, limit: Int = 3) -> [QuizQuestion] {
        let due = deck.cards.filter { $0.due <= now }.sorted { $0.due < $1.due }
        return Array(due.lazy.compactMap { card -> QuizQuestion? in
            let wrong = Distractors.pick(for: card, from: deck.cards)
            guard !wrong.isEmpty else { return nil }
            let options = ([QuizOption(text: card.definition, isCorrect: true)]
                + wrong.map { QuizOption(text: $0, isCorrect: false) }).shuffled()
            return QuizQuestion(cardID: card.id, term: card.term, meta: meta(card),
                                source: source(card.asked.last), options: options)
        }.prefix(limit))
    }

    static func meta(_ card: Card) -> String {
        "\(card.tags.first ?? "未分類") · 段 \(card.box)"
    }

    static func source(_ asked: Asked?) -> String {
        guard let asked else { return "" }
        let how: String
        switch asked.via {
        case .btw: how = "/btw で質問"
        case .term: how = "/term で質問"
        case .prompt: how = "会話で質問"
        }
        return "\(dayFormatter.string(from: asked.at)) · \(asked.project) · \(how)"
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter QuizSessionTests`
Expected: `Executed 9 tests, with 0 failures`

Run: `swift test`
Expected: すべて通る（本物の `claude` を呼ぶ1件は skip）

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 2: 出すかどうかの判定

**Files:**
- Create: `Sources/RecordoKit/QuizGate.swift`
- Test: `Tests/RecordoKitTests/QuizGateTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `enum QuizGate { static func needsSync(lastSyncAt: Date?, lastFailureAt: Date?, now: Date) -> Bool; static func isTimeToAsk(lastShownAt: Date?, interval: TimeInterval, now: Date) -> Bool; static func inQuietHours(_ date: Date, start: Int, end: Int, calendar: Calendar = .current) -> Bool; static func focusActive(assertionsURL: URL = QuizGate.assertionsURL) -> Bool; static var assertionsURL: URL; static func frontmostIsFullScreen() -> Bool }`（`start`、`end` は0時からの分）

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/QuizGateTests.swift`:

```swift
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter QuizGateTests`
Expected: コンパイルエラー `cannot find 'QuizGate' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/QuizGate.swift`:

```swift
import AppKit

enum QuizGate {
    static let syncInterval: TimeInterval = 24 * 3600
    static let retryAfterFailure: TimeInterval = 3600

    // Without the failure wait, a logged-out claude would be retried every 60-second tick.
    static func needsSync(lastSyncAt: Date?, lastFailureAt: Date?, now: Date) -> Bool {
        if let lastFailureAt, now.timeIntervalSince(lastFailureAt) < retryAfterFailure { return false }
        guard let lastSyncAt else { return true }
        return now.timeIntervalSince(lastSyncAt) >= syncInterval
    }

    static func isTimeToAsk(lastShownAt: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let lastShownAt else { return true }
        return now.timeIntervalSince(lastShownAt) >= interval
    }

    static func inQuietHours(_ date: Date, start: Int, end: Int, calendar: Calendar = .current) -> Bool {
        guard start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    static var assertionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    // Only manually or timer-started Focus lands in this file; scheduled Focus is covered by quiet hours.
    static func focusActive(assertionsURL: URL = QuizGate.assertionsURL) -> Bool {
        guard let data = try? Data(contentsOf: assertionsURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let first = (root["data"] as? [[String: Any]])?.first,
              let records = first["storeAssertionRecords"] as? [Any] else { return false }
        return !records.isEmpty
    }

    // ponytail: window-size heuristic; full-screen has no public API for other apps.
    static func frontmostIsFullScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        for window in info where (window[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let size = CGSize(width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if screenSizes.contains(where: { abs($0.width - size.width) < 2 && abs($0.height - size.height) < 2 }) {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter QuizGateTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 本物の Assertions.json を読めるか確かめる**

設計書の「実装時に確かめること」の1つ。テストの外で、実際のファイルが読めるかを見る（中身は表示しない）。

Run:
```bash
f="$HOME/Library/DoNotDisturb/DB/Assertions.json"
test -r "$f" && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("readable; records:", len(d.get("data",[{}])[0].get("storeAssertionRecords",[])))' "$f" || echo "not readable"
```
Expected: `readable; records: 0`（集中モードがオフのとき）。`not readable` なら、設計書の「実装時に確かめること」に結果を書き、`focusActive` が常に false になる（静かな時間帯と全画面だけで止める）ことをユーザーに伝える。Finder から起動した `.app` で読めるかは Task 7 で確かめる。

- [ ] **Step 6: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 3: 状態のまとめ役と設定のキー

**Files:**
- Create: `Sources/RecordoKit/Settings.swift`（この Task ではキーだけ。設定ウィンドウは Task 6 で足す）
- Create: `Sources/RecordoKit/AppModel.swift`
- Test: `Tests/RecordoKitTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `CardStore`、`CardStoreError`、`Importer.live(claudePathOverride:)`、`Importer.sync(progress:)`、`ClaudeError`（計画1）、`QuizSession`、`QuizQuestion`（Task 1）、`QuizGate`（Task 2）
- Produces:
  - `enum SettingsKey { static let intervalHours, quietEnabled, quietStart, quietEnd, claudePath: String; static func registerDefaults(_:) }`
  - `enum QuizNotice: Equatable { case noCards, nothingDue(next: Date, count: Int), unreadable }`
  - `@MainActor final class AppModel: ObservableObject { static let shared; enum SyncState: Equatable { case idle, syncing(done: Int, total: Int), failed(String) }; deck; unreadable; syncState; panelVisible; isSyncing; dueCount; lastSyncText; start(); tick(now:); showNow(); sync(); static func notice(for:now:) -> QuizNotice; static func noticeCopy(_:now:calendar:) -> (title: String, message: String); static func message(for: Error) -> String; static func lastSyncText(_:now:calendar:) -> String }`
  - `AppModel` が Task 4 以降に求めるもの：`QuizPanel`（`show(_:onClose:)`、`close()`、`adjust(to:)`）、`QuizView(session:onClose:onSize:)`、`QuizNoticeView(notice:onClose:onSync:onReveal:onSize:)`。この Task ではまだ無いので、Step 3 で最小の仮の型を置き、Task 4 と 5 で本物に置き換える。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/AppModelTests.swift`:

```swift
import XCTest
@testable import RecordoKit

@MainActor
final class AppModelTests: XCTestCase {
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
        XCTAssertEqual(due.message, "次は今日 21:40 に 2 枚の期限が来ます。")
        XCTAssertEqual(AppModel.noticeCopy(.nothingDue(next: date(24, 9), count: 1), now: now, calendar: calendar).message,
                       "次は明日 9:00 に 1 枚の期限が来ます。")
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

    func testLastSyncText() {
        let now = date(23, 19, 42)
        XCTAssertEqual(AppModel.lastSyncText(nil, now: now, calendar: calendar), "まだ同期していません")
        XCTAssertEqual(AppModel.lastSyncText(date(23, 19, 4), now: now, calendar: calendar), "今日 19:04")
        XCTAssertEqual(AppModel.lastSyncText(date(20, 8, 5), now: now, calendar: calendar), "9/20 8:05")
    }
}
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter AppModelTests`
Expected: コンパイルエラー `cannot find 'AppModel' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/Settings.swift`（この時点の内容。Task 6 で `SettingsView` を下に足す）:

```swift
import SwiftUI

enum SettingsKey {
    static let intervalHours = "quizIntervalHours"
    static let quietEnabled = "quietEnabled"
    static let quietStart = "quietStartMinutes"
    static let quietEnd = "quietEndMinutes"
    static let claudePath = "claudePath"

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            intervalHours: 3,
            quietEnabled: false,
            quietStart: 22 * 60,
            quietEnd: 9 * 60,
        ])
    }
}
```

`Sources/RecordoKit/AppModel.swift`:

```swift
import AppKit
import SwiftUI

enum QuizNotice: Equatable {
    case noCards
    case nothingDue(next: Date, count: Int)
    case unreadable
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum SyncState: Equatable {
        case idle
        case syncing(done: Int, total: Int)
        case failed(String)
    }

    @Published private(set) var deck = Deck()
    @Published private(set) var unreadable = false
    @Published private(set) var syncState = SyncState.idle
    @Published private(set) var panelVisible = false

    let store = CardStore(url: CardStore.defaultURL())
    private let panel = QuizPanel()
    private var timer: Timer?
    private var lastSyncFailureAt: Date?

    var isSyncing: Bool {
        if case .syncing = syncState { return true }
        return false
    }

    var dueCount: Int {
        let now = Date()
        return deck.cards.filter { $0.due <= now }.count
    }

    var lastSyncText: String { Self.lastSyncText(deck.lastSyncAt, now: Date()) }

    func start() {
        SettingsKey.registerDefaults()
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.tick() }
        }
        tick()
    }

    func reload() {
        do {
            deck = try store.load()
            unreadable = false
        } catch {
            unreadable = true
        }
    }

    func tick(now: Date = Date()) {
        guard !unreadable, !isSyncing, !panelVisible else { return }
        if QuizGate.needsSync(lastSyncAt: deck.lastSyncAt, lastFailureAt: lastSyncFailureAt, now: now) {
            sync()
            return
        }
        let defaults = UserDefaults.standard
        let interval = TimeInterval(max(1, defaults.integer(forKey: SettingsKey.intervalHours))) * 3600
        guard QuizGate.isTimeToAsk(lastShownAt: deck.lastShownAt, interval: interval, now: now),
              deck.cards.contains(where: { $0.due <= now }) else { return }
        if defaults.bool(forKey: SettingsKey.quietEnabled),
           QuizGate.inQuietHours(now, start: defaults.integer(forKey: SettingsKey.quietStart),
                                 end: defaults.integer(forKey: SettingsKey.quietEnd)) { return }
        guard !QuizGate.focusActive(), !QuizGate.frontmostIsFullScreen() else { return }
        presentQuiz(now: now)
    }

    /// 今すぐ出題 ignores the interval and the quiet checks, but never runs during a sync.
    func showNow() {
        guard !isSyncing else { return }
        reload()
        let now = Date()
        if unreadable {
            present(.unreadable)
        } else if !presentQuiz(now: now) {
            present(Self.notice(for: deck, now: now))
        }
    }

    @discardableResult
    private func presentQuiz(now: Date) -> Bool {
        let questions = QuizSession.questions(from: deck, now: now)
        guard !questions.isEmpty else { return false }
        deck.lastShownAt = now
        save()
        let session = QuizSession(
            questions: questions,
            onAnswer: { [weak self] id, correct in self?.answer(id, correct: correct) },
            onDiscard: { [weak self] id in self?.discard(id) })
        panelVisible = true
        panel.show(
            QuizView(session: session,
                     onClose: { [weak self] in self?.panel.close() },
                     onSize: { [weak self] size in self?.panel.adjust(to: size) }),
            onClose: { [weak self] in
                session.finish()
                self?.panelVisible = false
            })
        return true
    }

    private func present(_ notice: QuizNotice) {
        panelVisible = true
        panel.show(
            QuizNoticeView(notice: notice,
                           onClose: { [weak self] in self?.panel.close() },
                           onSync: { [weak self] in
                               self?.panel.close()
                               self?.sync()
                           },
                           onReveal: { [weak self] in
                               guard let self else { return }
                               NSWorkspace.shared.activateFileViewerSelecting([self.store.url])
                           },
                           onSize: { [weak self] size in self?.panel.adjust(to: size) }),
            onClose: { [weak self] in self?.panelVisible = false })
    }

    private func answer(_ id: UUID, correct: Bool) {
        deck.answer(cardID: id, correct: correct, now: Date())
        save()
    }

    private func discard(_ id: UUID) {
        deck.remove(cardID: id)
        save()
    }

    // The write is atomic, so a failure keeps the previous file and loses only this one change.
    private func save() {
        try? store.save(deck)
    }

    func sync() {
        guard !isSyncing, !panelVisible else { return }
        syncState = .syncing(done: 0, total: 0)
        let override = UserDefaults.standard.string(forKey: SettingsKey.claudePath)
        Task { @MainActor in
            do {
                // The login-shell lookup can take a second; keep it off the main thread.
                let importer = try await Task.detached { try Importer.live(claudePathOverride: override) }.value
                try await importer.sync { done, total in
                    Task { @MainActor in
                        if AppModel.shared.isSyncing { AppModel.shared.syncState = .syncing(done: done, total: total) }
                    }
                }
                lastSyncFailureAt = nil
                syncState = .idle
            } catch {
                lastSyncFailureAt = Date()
                syncState = .failed(Self.message(for: error))
            }
            reload()
        }
    }

    static func notice(for deck: Deck, now: Date) -> QuizNotice {
        guard !deck.cards.isEmpty else { return .noCards }
        let next = deck.cards.map(\.due).filter { $0 > now }.min() ?? now
        let count = deck.cards.filter { $0.due <= next.addingTimeInterval(60) }.count
        return .nothingDue(next: next, count: count)
    }

    static func noticeCopy(_ notice: QuizNotice, now: Date, calendar: Calendar = .current) -> (title: String, message: String) {
        switch notice {
        case .noCards:
            return ("まだカードがありません", "Claude Code で用語の意味を聞くと、次の同期でカードになります。")
        case let .nothingDue(next, count):
            return ("今出せるカードはありません", "次は\(when(next, now: now, calendar: calendar)) に \(count) 枚の期限が来ます。")
        case .unreadable:
            return ("cards.json を読めませんでした", "ファイルを直すまで、取り込みと出題を止めています。")
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case ClaudeError.notFound: return "claude が見つかりません。設定で場所を指定してください"
        case ClaudeError.notLoggedIn: return "claude にログインしてください"
        case CardStoreError.unreadable: return "cards.json を読めませんでした"
        default: return "claude の応答を読めませんでした"
        }
    }

    static func lastSyncText(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return "まだ同期していません" }
        return when(date, now: now, calendar: calendar)
    }

    private static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = formatter("H:mm", calendar)
        if calendar.isDate(date, inSameDayAs: now) { return "今日 \(time.string(from: date))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明日 \(time.string(from: date))"
        }
        return formatter("M/d H:mm", calendar).string(from: date)
    }

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
```

この Task の時点では `QuizPanel`、`QuizView`、`QuizNoticeView` がまだ無い。コンパイルを通すため、`Sources/RecordoKit/QuizPanel.swift`、`QuizView.swift`、`QuizNoticeView.swift` に仮の型を置く（Task 4 と 5 でファイルごと置き換える）:

```swift
// Sources/RecordoKit/QuizPanel.swift (placeholder until Task 4)
import AppKit
import SwiftUI

final class QuizPanel: NSPanel {
    func show<Content: View>(_ view: Content, onClose: @escaping () -> Void) {}
    func adjust(to content: CGSize) {}
}
```

```swift
// Sources/RecordoKit/QuizView.swift (placeholder until Task 5)
import SwiftUI

struct QuizView: View {
    @ObservedObject var session: QuizSession
    let onClose: () -> Void
    let onSize: (CGSize) -> Void
    var body: some View { EmptyView() }
}
```

```swift
// Sources/RecordoKit/QuizNoticeView.swift (placeholder until Task 5)
import SwiftUI

struct QuizNoticeView: View {
    let notice: QuizNotice
    let onClose: () -> Void
    let onSync: () -> Void
    let onReveal: () -> Void
    let onSize: (CGSize) -> Void
    var body: some View { EmptyView() }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter AppModelTests`
Expected: `Executed 4 tests, with 0 failures`

Run: `swift test`
Expected: すべて通る

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 4: 色、部品、小窓

**Files:**
- Create: `Sources/RecordoKit/Theme.swift`
- Create: `Sources/RecordoKit/QuizStyle.swift`
- Modify: `Sources/RecordoKit/QuizPanel.swift`（仮の型を置き換える）

**Interfaces:**
- Consumes: なし（以前作った別のアプリの `Theme`、`QuizStyle`、`QuizPanel` を移植）
- Produces:
  - `enum Theme { window, inset, text, secondary, line, action, success, bad, correctFace, wrongFace: Color }`、`View.clickCursor(_:)`
  - `enum QuizTypography`、`enum QuizStyle`、`enum QuizMotion { reveal, press, pop, swap }`
  - `QuizPanelFrame(scrollTarget:header:body:actions:)`、`QuizOptionsView(options:picked:answered:onPick:)`、`QuizQuietButtonStyle`、`QuizPrimaryButtonStyle`、`QuizPrimaryLabel(title:)`、`QuizCloseButton(action:)`、`View.quizSurface(onSize:)`
  - `final class QuizPanel: NSPanel { show(_:onClose:); close(); adjust(to:) }`

このタスクは見た目の部品なのでテストは書かない。`swift build` が通ることと、Task 7 で画面を見て確かめる。

- [ ] **Step 1: 色とカーソル**

`Sources/RecordoKit/Theme.swift`:

```swift
import AppKit
import SwiftUI

// Values from an earlier app's quiz theme, so both apps read as one family.
enum Theme {
    static let window = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let inset = adaptive(light: 0xF5F5F7, dark: 0x2C2C2E)
    static let text = adaptive(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let secondary = adaptive(light: 0x68686D, dark: 0xB5B5BB)
    static let line = adaptive(light: 0xDEDEE3, dark: 0x454549)
    static let action = adaptive(light: 0x0068D9, dark: 0x0071E3)
    static let success = adaptive(light: 0x267843, dark: 0x79D794)
    static let bad = adaptive(light: 0xB3261E, dark: 0xFF746D)
    static let correctFace = adaptive(light: 0xEDF7F0, dark: 0x173C29)
    static let wrongFace = adaptive(light: 0xFFF2F1, dark: 0x482321)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return NSColor(hex: isDark ? dark : light)
        }))
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension View {
    // Custom clickable surfaces show the pointing hand; disabled ones must not.
    func clickCursor(_ enabled: Bool = true) -> some View {
        onHover { inside in
            guard enabled else { return }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
```

- [ ] **Step 2: 文字、寸法、動き、部品**

`Sources/RecordoKit/QuizStyle.swift`:

```swift
import AppKit
import SwiftUI

// Values from the approved prototype (design/sessions/quiz) and an earlier app's quiz style.
enum QuizTypography {
    static let question: CGFloat = 22
    static let option: CGFloat = 14
    static let body: CGFloat = 13
    static let meta: CGFloat = 11
}

enum QuizStyle {
    static let width: CGFloat = 340
    static let maxHeight: CGFloat = 640
    static let gutter: CGFloat = 20
    static let optionMinHeight: CGFloat = 48
}

/// Damping 1 everywhere except the verdict glyph, which is the one moment that earns a bounce.
enum QuizMotion {
    static func reveal(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.30, dampingFraction: 1)
    }

    static func press(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1)
    }

    static func pop(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.30, dampingFraction: 0.8)
    }

    static func swap(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.28, dampingFraction: 1)
    }
}

// MARK: - Panel frame

/// Header and footer stay fixed; only the body scrolls. Long definitions always fill the
/// body, which is why the verdict lives in the footer (see apple-quiz-spec.md).
struct QuizPanelFrame<Header: View, Body_: View, Actions: View>: View {
    let scrollTarget: String?
    @ViewBuilder let header: Header
    @ViewBuilder let body_: Body_
    @ViewBuilder let actions: Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0

    init(scrollTarget: String? = nil,
         @ViewBuilder header: () -> Header,
         @ViewBuilder body: () -> Body_,
         @ViewBuilder actions: () -> Actions) {
        self.scrollTarget = scrollTarget
        self.header = header()
        self.body_ = body()
        self.actions = actions()
    }

    private var bodyCap: CGFloat { QuizStyle.maxHeight - 170 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, QuizStyle.gutter)
                .padding(.top, 16)
                .padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { body_ }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, QuizStyle.gutter)
                        .padding(.bottom, 16)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: QuizBodyHeightKey.self, value: geometry.size.height)
                        })
                }
                .frame(height: min(max(contentHeight, 1), bodyCap))
                .scrollDisabled(contentHeight <= bodyCap)
                .onPreferenceChange(QuizBodyHeightKey.self) { contentHeight = $0 }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(QuizMotion.reveal(reduceMotion)) { proxy.scrollTo(target) }
                }
            }
            actions
                .padding(.horizontal, QuizStyle.gutter)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.inset)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }
}

private struct QuizBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Surface

/// Blurred backdrop for the transparent panel.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct QuizSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

/// Enters sliding up from the bottom-right, the same corner it leaves through; opacity only under Reduce Motion.
private struct QuizEnter: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown || reduceMotion ? 0 : 10, y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.22) : .spring(response: 0.30, dampingFraction: 1)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// The panel's width, material and self-measured height, shared by the quiz and the notices.
    func quizSurface(onSize: @escaping (CGSize) -> Void) -> some View {
        frame(width: QuizStyle.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(VisualEffect())
            .background(GeometryReader { proxy in
                Color.clear.preference(key: QuizSizeKey.self, value: proxy.size)
            })
            .onPreferenceChange(QuizSizeKey.self) { onSize($0) }
            .modifier(QuizEnter())
    }
}

// MARK: - Buttons

struct QuizCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("閉じる")
    }
}

/// `␣` after the primary label: the control Space activates. Decorative for VoiceOver.
struct QuizPrimaryLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
            Text(verbatim: "\u{2423}")
                .font(.system(size: 11))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .padding(.leading, 6)
                .accessibilityHidden(true)
        }
    }
}

struct QuizPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: QuizTypography.body, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.action, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(QuizMotion.press(reduceMotion), value: configuration.isPressed)
            .contentShape(Capsule())
            .clickCursor()
    }
}

/// The quiet inline control: 後で, 分からない, このカードを捨てる, 元に戻す.
struct QuizQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: QuizTypography.body))
            .foregroundStyle(Theme.action)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.inset : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(QuizMotion.press(reduceMotion), value: configuration.isPressed)
            .contentShape(Rectangle())
            .clickCursor(isEnabled)
    }
}

// MARK: - Options

struct QuizOptionsView: View {
    let options: [QuizOption]
    let picked: Int?
    let answered: Bool
    let onPick: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let keys = ["A", "B", "C", "D"]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                row(option, index: index)
                    .id("option-\(index)")
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 4)
                    .animation(reduceMotion ? nil : QuizMotion.reveal(false).delay(Double(index) * 0.03), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }

    private func row(_ option: QuizOption, index: Int) -> some View {
        let isCorrect = answered && option.isCorrect
        let isWrong = answered && !option.isCorrect && picked == index
        let key = Self.keys[min(index, Self.keys.count - 1)]
        return Button { onPick(index) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(key)
                    .font(.system(size: QuizTypography.meta, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(option.text)
                    .font(.system(size: QuizTypography.option))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if isCorrect || isWrong {
                    // A glyph as well as a colour, so the verdict never rests on colour alone.
                    Image(systemName: isCorrect ? "checkmark" : "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isCorrect ? Theme.success : Theme.bad)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(12)
            .frame(minHeight: QuizStyle.optionMinHeight, alignment: .top)
            .background(isCorrect ? Theme.correctFace : isWrong ? Theme.wrongFace : Theme.inset,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isCorrect ? Theme.success : isWrong ? Theme.bad : Theme.line, lineWidth: 1))
            .opacity(answered && !isCorrect && !isWrong ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuizOptionButtonStyle(answered: answered))
        .keyboardShortcut(KeyEquivalent(Character(key.lowercased())), modifiers: [])
        .clickCursor(!answered)
        // Answered rows stay readable and focusable; they just stop accepting a pick.
        .allowsHitTesting(!answered)
        .accessibilityLabel("\(key). \(option.text)")
        .accessibilityValue(isCorrect ? "正解" : isWrong ? "選んだ回答。不正解" : "")
    }
}

/// Pressed state arrives on pointer-down and springs back on release.
private struct QuizOptionButtonStyle: ButtonStyle {
    let answered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !answered && !reduceMotion ? 0.985 : 1)
            .animation(QuizMotion.press(reduceMotion), value: configuration.isPressed)
    }
}
```

- [ ] **Step 3: 小窓**

`Sources/RecordoKit/QuizPanel.swift`（仮の型をこの内容で置き換える）:

```swift
import AppKit
import SwiftUI

/// The corner popup. Non-activating, so a quiz never takes the keyboard from the app in use.
final class QuizPanel: NSPanel {
    private var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: QuizStyle.width, height: 320),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .closable],
            backing: .buffered,
            defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Hidden title bar means no visible text; the title still names the window for VoiceOver.
        title = "Recordo 出題"
        setAccessibilityTitle(title)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func show<Content: View>(_ view: Content, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let host = NSHostingView(rootView: view)
        // SwiftUI would resize the window top-anchored and walk it off screen; adjust(to:) owns the size.
        host.sizingOptions = []
        contentView = host
        alphaValue = 1
        if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 24, y: visible.minY + 24))
        }
        orderFrontRegardless()
    }

    override func close() {
        let callback = onClose
        onClose = nil
        callback?()
        guard isVisible else { return super.close() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.finishClose()
        })
    }

    private func finishClose() {
        super.close()
        alphaValue = 1
    }

    /// Grows and shrinks with the content, keeping the bottom-right corner pinned.
    func adjust(to content: CGSize) {
        let inset = contentView?.safeAreaInsets.top ?? 0
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        let heightCap = min(QuizStyle.maxHeight, (visible?.height ?? QuizStyle.maxHeight) - 48)
        let target = NSSize(width: max(content.width, 280),
                            height: min(max(content.height + inset, 160), max(heightCap, 160)))
        guard abs(frame.height - target.height) > 2 || abs(frame.width - target.width) > 2 else { return }
        var origin = frame.origin
        if let visible {
            origin.x = min(origin.x, visible.maxX - target.width - 24)
            origin.y = max(origin.y, visible.minY + 24)
        }
        setFrame(NSRect(origin: origin, size: target), display: true)
    }
}
```

- [ ] **Step 4: ビルドが通ることを確かめる**

Run: `swift build 2>&1 | grep -E "error|Build complete"`
Expected: `Build complete!`（`error` の行が出ない）

Run: `swift test`
Expected: すべて通る

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 5: 出題の画面と、出せないときの画面

**Files:**
- Modify: `Sources/RecordoKit/QuizView.swift`（仮の型を置き換える）
- Modify: `Sources/RecordoKit/QuizNoticeView.swift`（仮の型を置き換える）

**Interfaces:**
- Consumes: `QuizSession`、`Verdict`（Task 1）、`QuizNotice`、`AppModel.noticeCopy(_:now:calendar:)`（Task 3）、Task 4 の部品すべて
- Produces: `QuizView(session:onClose:onSize:)`、`QuizNoticeView(notice:onClose:onSync:onReveal:onSize:)`

答えた後の並びは試作どおり。正誤と「どこで聞いたか」は下端の固定の欄に出し、選択肢の下には出さない。正しい定義を答え合わせでもう一度出すこともしない。「後で」は答える前だけ、答えた後は左に「このカードを捨てる」、右に「次へ」（最後の問題は「閉じる」）。

- [ ] **Step 1: 出題の画面**

`Sources/RecordoKit/QuizView.swift`（仮の型をこの内容で置き換える）:

```swift
import SwiftUI

struct QuizView: View {
    @ObservedObject var session: QuizSession
    let onClose: () -> Void
    let onSize: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollTarget: String?

    var body: some View {
        QuizPanelFrame(scrollTarget: scrollTarget) {
            HStack {
                Text("復習 \(session.index + 1)/\(session.questions.count)")
                    .font(.system(size: QuizTypography.body, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                QuizCloseButton(action: onClose)
            }
        } body: {
            question
                .id(session.index)
                .transition(questionTransition)
        } actions: {
            footer
        }
        .quizSurface(onSize: onSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recordo 出題")
    }

    private var question: some View {
        let current = session.current
        return VStack(alignment: .leading, spacing: 0) {
            Text(current.meta)
                .font(.system(size: QuizTypography.meta))
                .foregroundStyle(Theme.secondary)
            Text(current.term)
                .font(.system(size: QuizTypography.question, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 16)
            QuizOptionsView(options: current.options, picked: session.picked, answered: session.verdict != nil) { index in
                answer { session.pick(index) }
            }
            if session.verdict == nil {
                Button("分からない") { answer { session.dontKnow() } }
                    .buttonStyle(QuizQuietButtonStyle())
                    .padding(.top, 8)
            }
        }
    }

    private var questionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .offset(x: 16).combined(with: .opacity),
                          removal: .offset(x: -16).combined(with: .opacity))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let verdict = session.verdict {
                verdictLine(verdict)
                    .transition(reduceMotion ? .opacity : .offset(y: 6).combined(with: .opacity))
            }
            HStack(spacing: 8) {
                leading
                Spacer(minLength: 8)
                if session.verdict != nil {
                    Button { next() } label: { QuizPrimaryLabel(title: session.isLast ? "閉じる" : "次へ") }
                        .buttonStyle(QuizPrimaryButtonStyle())
                        .keyboardShortcut(.space, modifiers: [])
                        .help("Space")
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if session.verdict == nil {
            Button("後で", action: onClose)
                .buttonStyle(QuizQuietButtonStyle())
        } else if session.discarded {
            HStack(spacing: 2) {
                Text("捨てました")
                    .font(.system(size: QuizTypography.body))
                    .foregroundStyle(Theme.secondary)
                Button("元に戻す") { withAnimation(.easeOut(duration: 0.15)) { session.undo() } }
                    .buttonStyle(QuizQuietButtonStyle())
            }
            .transition(.opacity)
        } else {
            Button("このカードを捨てる") { withAnimation(.easeOut(duration: 0.15)) { session.discard() } }
                .buttonStyle(QuizQuietButtonStyle())
                .transition(.opacity)
        }
    }

    private func verdictLine(_ verdict: Verdict) -> some View {
        let current = session.current
        let title: String
        let color: Color
        let glyph: String?
        switch verdict {
        case .correct: (title, color, glyph) = ("正解", Theme.success, "checkmark")
        case .wrong: (title, color, glyph) = ("不正解", Theme.bad, "xmark")
        case .dontKnow: (title, color, glyph) = ("正しい答えは \(["A", "B", "C", "D"][min(current.correctIndex, 3)])", Theme.text, nil)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 3) {
                if let glyph { Image(systemName: glyph).font(.system(size: 12, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            Text(current.source)
                .font(.system(size: QuizTypography.meta))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func answer(_ change: () -> Void) {
        withAnimation(QuizMotion.pop(reduceMotion)) { change() }
        scrollTarget = "option-\(session.current.correctIndex)"
    }

    private func next() {
        scrollTarget = nil
        let more = withAnimation(QuizMotion.swap(reduceMotion)) { session.advance() }
        if !more { onClose() }
    }
}
```

- [ ] **Step 2: 出せないときの画面**

`Sources/RecordoKit/QuizNoticeView.swift`（仮の型をこの内容で置き換える）:

```swift
import SwiftUI

/// Says which of the three reasons it is and offers the way out, instead of an empty panel.
struct QuizNoticeView: View {
    let notice: QuizNotice
    let onClose: () -> Void
    let onSync: () -> Void
    let onReveal: () -> Void
    let onSize: (CGSize) -> Void

    var body: some View {
        let copy = AppModel.noticeCopy(notice, now: Date())
        QuizPanelFrame {
            HStack {
                Text("Recordo")
                    .font(.system(size: QuizTypography.body, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                QuizCloseButton(action: onClose)
            }
        } body: {
            VStack(alignment: .leading, spacing: 8) {
                Text(copy.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(copy.message)
                    .font(.system(size: QuizTypography.body))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        } actions: {
            HStack(spacing: 8) {
                Spacer()
                switch notice {
                case .noCards:
                    Button("閉じる", action: onClose).buttonStyle(QuizQuietButtonStyle())
                    Button("今すぐ同期", action: onSync).buttonStyle(QuizPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                case .nothingDue:
                    Button("閉じる", action: onClose).buttonStyle(QuizPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                case .unreadable:
                    Button("Finder で表示", action: onReveal).buttonStyle(QuizQuietButtonStyle())
                    Button("閉じる", action: onClose).buttonStyle(QuizPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .quizSurface(onSize: onSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recordo")
    }
}
```

- [ ] **Step 3: ビルドとテスト**

Run: `swift build 2>&1 | grep -E "error|Build complete"`
Expected: `Build complete!`

Run: `swift test`
Expected: すべて通る

- [ ] **Step 4: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 6: 設定ウィンドウ、メニュー、アプリの入口

**Files:**
- Modify: `Sources/RecordoKit/Settings.swift`（`SettingsView` を足す）
- Create: `Sources/RecordoKit/RecordoApp.swift`
- Modify: `Sources/Recordo/main.swift`（全体を置き換える）

**Interfaces:**
- Consumes: `AppModel`（Task 3）、`SettingsKey`、`ClaudePath`、`Importer`（計画1）
- Produces: `public enum RecordoMain { @MainActor public static func run(arguments: [String]) }`、`SettingsView`、`RecordoApp`、`MenuContent`。起動引数 `--sync-once`（計画1の CLI）と `--quiz-now`（起動直後に「今すぐ出題」。画面の確認用）

メニューは SwiftUI の `MenuBarExtra(.menu)`、つまり macOS 標準のメニューになる。試作との違いは次の3点で、どれも標準メニューの制約による：
- 「期限 5 枚」は右寄せにできないので、「今すぐ出題（期限 5 枚）」とラベルに入れる
- 同期中の回るマークは出せないので、「同期中 3/11」の文字だけにする
- メニューが開く動きは OS の標準のまま（試作の拡大フェードは入れない）

- [ ] **Step 1: 設定ウィンドウ**

`Sources/RecordoKit/Settings.swift` の末尾に足す:

```swift
struct SettingsView: View {
    @AppStorage(SettingsKey.intervalHours) private var intervalHours = 3
    @AppStorage(SettingsKey.quietEnabled) private var quietEnabled = false
    @AppStorage(SettingsKey.quietStart) private var quietStart = 22 * 60
    @AppStorage(SettingsKey.quietEnd) private var quietEnd = 9 * 60
    @AppStorage(SettingsKey.claudePath) private var claudePath = ""
    @State private var claudeStatus = "探しています…"

    var body: some View {
        Form {
            Picker("出題の間隔", selection: $intervalHours) {
                ForEach([1, 2, 3, 4, 6], id: \.self) { Text("\($0) 時間").tag($0) }
            }
            LabeledContent("静かな時間帯") {
                HStack(spacing: 6) {
                    DatePicker("開始", selection: time($quietStart), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("〜")
                    DatePicker("終了", selection: time($quietEnd), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Toggle("静かな時間帯", isOn: $quietEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("claude の場所", text: $claudePath, prompt: Text("自動で探す"))
                Text(claudeStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .task(id: claudePath) {
            let override = claudePath
            let found = await Task.detached {
                ClaudePath.resolve(override: override, lookup: ClaudePath.loginShellLookup)?.path
            }.value
            claudeStatus = found.map { "見つかりました：\(($0 as NSString).abbreviatingWithTildeInPath)" }
                ?? "見つかりません。claude の場所を入力してください"
        }
    }

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}
```

- [ ] **Step 2: アプリの入口とメニュー**

`Sources/RecordoKit/RecordoApp.swift`:

```swift
import AppKit
import SwiftUI

public enum RecordoMain {
    @MainActor
    public static func run(arguments: [String]) {
        if arguments.contains("--sync-once") {
            // Line buffering keeps the progress lines live when output goes to a pipe or a log.
            setvbuf(stdout, nil, _IOLBF, 0)
            Task { @MainActor in await syncOnce() }
            dispatchMain()
        }
        RecordoApp.main()
    }

    @MainActor
    private static func syncOnce() async {
        do {
            let changed = try await Importer.live().sync { done, total in print("同期中 \(done)/\(total)") }
            print("\(changed) 件のカードを追加または最初の段に戻しました")
            exit(0)
        } catch {
            print("同期に失敗しました: \(error)")
            exit(1)
        }
    }
}

struct RecordoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Recordo", systemImage: "rectangle.stack") {
            MenuContent(model: model)
        }
        .menuBarExtraStyle(.menu)
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon even for `swift run`, whose binary has no Info.plist with LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppModel.shared.start()
            if CommandLine.arguments.contains("--quiz-now") { AppModel.shared.showNow() }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(model.dueCount > 0 ? "今すぐ出題（期限 \(model.dueCount) 枚）" : "今すぐ出題") { model.showNow() }
            .disabled(model.isSyncing)
        switch model.syncState {
        case let .syncing(done, total):
            Text(total > 0 ? "同期中 \(done)/\(total)" : "同期の準備中…")
        case .idle, .failed:
            Button("今すぐ同期") { model.sync() }
                .disabled(model.panelVisible)
        }
        if case let .failed(message) = model.syncState {
            Text("⚠︎ 同期できませんでした：\(message)")
        }
        Divider()
        Text("最後の同期：\(model.lastSyncText)")
        Divider()
        Button("設定…") {
            // An accessory app's Settings window opens behind the frontmost app unless we activate first.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Recordo を終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
```

`Sources/Recordo/main.swift`（全体を置き換える）:

```swift
import RecordoKit

MainActor.assumeIsolated {
    RecordoMain.run(arguments: CommandLine.arguments)
}
```

- [ ] **Step 3: ビルドとテスト**

Run: `swift build 2>&1 | grep -E "error|Build complete"`
Expected: `Build complete!`

Run: `swift test`
Expected: すべて通る

Run: `swift run Recordo --sync-once`
Expected: 計画1と同じく `同期中 1/1` と `… 件のカードを追加または最初の段に戻しました` が出て終わる（前回の同期以降の質問がなければ `同期中` は出ず `0 件` で終わる）。

- [ ] **Step 4: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 7: .app の作成、起動、画面での確認

**Files:**
- Create: `scripts/bundle.sh`
- Modify: `Makefile`
- Modify: `.gitignore`
- Modify: `AGENTS.md`（コマンドの節）
- Modify: `docs/superpowers/specs/2026-09-23-recordo-design.md`（出題の節、実装時に確かめること）
- Modify: `design/README.md`（状態を「承認済み」に）

**Interfaces:**
- Consumes: Task 1〜6 のすべて
- Produces: `make dev`、`make app`、`make install`、`build.noindex/Recordo.app`

- [ ] **Step 1: .app を作るスクリプト**

`scripts/bundle.sh`（作ったら `chmod +x scripts/bundle.sh`）:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Recordo"
BUNDLE_ID="app.recordo"
VERSION="0.1.0"
# .noindex keeps Spotlight from listing the built .app as a second copy.
BUILD_DIR="build.noindex"
APP="$BUILD_DIR/$APP_NAME.app"

# No bundled resources, so plain swift build is enough (Bundle.module would need xcodebuild).
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# A stable Apple Development identity keeps privacy grants across rebuilds; "-" is ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}' || true)
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
```

- [ ] **Step 2: Makefile と .gitignore**

`Makefile` を次の内容にする（レシピの行頭はタブ文字）:

```make
.PHONY: test dev sync app install install-skill clean

test:
	swift test

# swift run builds have no bundle id, so dev runs read and write dev-cards.json.
dev:
	swift build
	"$$(swift build --show-bin-path)/Recordo"

# Refuse while the app runs: its in-memory cards would overwrite what this sync saves.
sync:
	@! pgrep -x Recordo >/dev/null || { echo "Recordo is running; quit it before make sync" >&2; exit 1; }
	swift run Recordo --sync-once

app:
	./scripts/bundle.sh

install: app
	@killall Recordo 2>/dev/null || true
	rm -rf /Applications/Recordo.app
	cp -R build.noindex/Recordo.app /Applications/
	open /Applications/Recordo.app

install-skill:
	mkdir -p "$(HOME)/.claude/skills"
	ln -sfn "$(CURDIR)/skills/term" "$(HOME)/.claude/skills/term"

clean:
	rm -rf .build build.noindex
```

`.gitignore` に1行足す:

```
build.noindex/
```

- [ ] **Step 3: .app を作る**

Run: `make app`
Expected: 最後に `Built build.noindex/Recordo.app (signed with: …)`

- [ ] **Step 4: 開発ビルドで小窓を見る**

`make dev` は終わらない（アプリが動き続ける）ので、裏で起動する。確認用に `--quiz-now` で起動直後に出題させる。`dev-cards.json` に期限の来たカードがない場合は「今出せるカードはありません」の画面が出る。

Run（裏で起動）:
```bash
swift build && "$(swift build --show-bin-path)/Recordo" --quiz-now &
```

小窓のウィンドウだけを撮る（画面全体は撮らない。ほかのウィンドウの内容が写るため）。撮影には `screencapture -l <ウィンドウ番号>` を使い、番号は次の Swift スクリプトで探す:

```bash
cat > "$TMPDIR/recordo-window.swift" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Recordo" && (w[kCGWindowLayer as String] as? Int ?? 0) > 0 {
    print(w[kCGWindowNumber as String] as? Int ?? 0)
}
SWIFT
id=$(swift "$TMPDIR/recordo-window.swift" | head -1)
screencapture -x -o -l "$id" "$TMPDIR/recordo-quiz.png" && echo "$TMPDIR/recordo-quiz.png"
```

撮った画像を開いて、試作と比べて確かめる：
- 右下に出ている。ターミナルなど作業中のアプリのキー入力を奪っていない（小窓が出た後も、ターミナルに文字を打てる）
- 「復習 1/3」、分野と段、用語、A〜D の選択肢、「分からない」、下端の「後で」
- 選択肢の文字が切れずに折り返している。本文だけがスクロールし、下端は動かない

次に、実際に操作して確かめる。キーボードやマウスを勝手に動かさず、ユーザーに次を操作してもらうか、Accessibility API で押す：
- 選択肢を押す → 行の色、✓ と ✗、下端の「正解」または「不正解」と「どこで聞いたか」、「このカードを捨てる」、「次へ」
- 「このカードを捨てる」→「捨てました 元に戻す」、「元に戻す」で戻る
- Space または「次へ」→ 次の問題が右から入る。3問目の後は「閉じる」
- ✕ と Esc で閉じる。閉じた後、`dev-cards.json` の該当カードの `box`、`due`、`reviews` が変わっている

- [ ] **Step 5: ダーク、動きなし、メニュー、設定**

- システム設定でダークモードに切り替え、同じ手順で小窓を撮って試作のダークと比べる
- システム設定の「視差効果を減らす」をオンにして、動きがフェードだけになることを見る（見終わったら元に戻す）
- メニューバーのアイコンを開き、「今すぐ出題（期限 N 枚）」「今すぐ同期」「最後の同期：…」「設定…」「Recordo を終了」を確かめる。「今すぐ同期」の後に「同期中 1/1」になり、終わると戻る
- 「設定…」で設定ウィンドウが手前に開く。「claude の場所」の下に「見つかりました：~/…/claude」と出る
- 期限の来たカードがない状態で「今すぐ出題」を押し、「今出せるカードはありません」と次の期限が出る

動作を確かめたら、開発ビルドを終了する（メニューの「Recordo を終了」）。

- [ ] **Step 6: .app で確かめる**

Run: `make install`
Expected: `/Applications/Recordo.app` が起動し、Dock にアイコンが出ず、メニューバーにアイコンが出る。

- `.app` は普段使いの `cards.json` を使う。初回はカードがないので、起動後すぐに裏で30日分の同期が始まる（約30分、メニューに「同期中 n/N」）。
- Finder から起動した `.app` で `Assertions.json` を読めるかは、ユーザーに集中モードをオンにしてもらい、「今すぐ出題」ではなく自動の出題が止まることで確かめる（自動の出題は3時間おきなので、確認のときは設定の「出題の間隔」を1時間にする）。確かめられなかった場合は、そのまま報告する。

- [ ] **Step 7: 文書を更新する**

- `AGENTS.md` のコマンドの節に `make dev`、`make app`、`make install` を足し、`make sync` はアプリを終了してから使うことを書く。
- 設計書の「1回の出題」を、答えた後の並び（下端の欄に正誤とどこで聞いたか、正しい定義は ✓ の行、「後で」は答える前だけ、「このカードを捨てる」は元に戻せる）に合わせて直す。「画面の作り方」に、試作が 2026-09-23 に承認されたことと、メニューの3つの違い（右寄せなし、回るマークなし、開く動きは OS の標準）を書く。「実装時に確かめること」から、この計画で確かめた項目を消し、結果を本文に移す。
- `design/README.md` の見出しを「出題の小窓・メニュー・設定：承認済み（2026-09-23）」にする。

- [ ] **Step 8: 区切りの確認**

Run: `swift test && git status --short && git diff --cached --stat`
Expected: テストがすべて通り、`git diff --cached --stat` は何も出さない。コミットはせず、計画2の完了を報告する。報告には、撮った画面の確認結果、ユーザーに確かめてもらう必要が残った項目（集中モード、全画面のアプリの上での抑止）を含める。

---

## 実装時に確かめること（この計画の中で）

- SwiftUI の `.keyboardShortcut` が、キーになった非アクティブな `NSPanel` の中で効くか（A〜D、Space、Esc）。効かなければ `NSEvent` のローカルモニターで受ける。
- `@Environment(\.openSettings)` が `MenuBarExtra` のメニューの中で使えるか。使えなければ `SettingsLink` に置き換える。
- `NSHostingView` の `sizingOptions = []` と `quizSurface` の大きさの測り方で、小窓が内容の高さに合うか。
