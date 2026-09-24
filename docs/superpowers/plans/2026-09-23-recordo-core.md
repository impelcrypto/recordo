# Recordo 計画1：中身（データ、Leitner、取り込み）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 画面を持たない Recordo の中身を作り、`swift run Recordo --sync-once` で本物の `history.jsonl` から `dev-cards.json` にカードを取り込めるようにする。

**Architecture:** SwiftPM のパッケージで、ロジックはすべてライブラリ `RecordoKit` に置き、実行ファイル `Recordo` は `main.swift` だけにする。取り込みは `Importer` が `HistoryReader`（質問の読み込み）、`TranscriptReader`（会話の切り出し）、`ClaudeRunning`（`claude -p` の呼び出し）、`CardStore`（`cards.json` の読み書き）を順に呼ぶ。画面（出題の小窓、メニューバー、設定）は計画2で、HTML の試作が承認されてから書く。

**Tech Stack:** Swift 6.4 ツールチェーン（`swift-tools-version: 6.0`、言語モード Swift 5）、Foundation、XCTest。外部の依存パッケージなし。

**設計書:** `docs/superpowers/specs/2026-09-23-recordo-design.md`

## Global Constraints

- `git add`、`git commit`、`git push` は実行しない。コミットはユーザーが行う。各タスクの最後は `git status --short` で変更を確認し、`git diff --cached --stat` が空であることを確かめて区切りを報告する。
- `Package.swift` は `swift-tools-version: 6.0`、`platforms: [.macOS(.v14)]`、全ターゲットに `.swiftLanguageMode(.v5)`。依存パッケージは追加しない。
- テストは XCTest。本物の `claude -p` を呼ぶテストは `CLAUDE_LIVE=1` のときだけ動かし、それ以外は `XCTSkip` にする。
- テストのフィクスチャは架空の内容で作る（用語は `foo-rate`、`bar-cache` など）。本物の `~/.claude/history.jsonl` やセッション記録の中身をコピーしない。
- `claude -p` は必ず環境変数 `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` と `--no-session-persistence` を付けて呼ぶ。付けないと Recordo が送ったプロンプトが `history.jsonl` に入り、次の同期で自分自身を取り込む。
- `public` は `RecordoKit` の外（`Sources/Recordo/main.swift`）から使うものだけに付ける。計画1では `Importer`、`Importer.live(claudePathOverride:)`、`Importer.sync(progress:)` の3つ。テストは `@testable import RecordoKit` で内部の型を使う。
- コードのコメントは英語で2行まで。何をしているかではなく、なぜそうするかだけを書く。
- `cards.json` の日付は ISO 8601（秒まで）。`importedThrough` はミリ秒の `Int`。
- UI に出す文言と LLM へのプロンプトは日本語。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `Package.swift` | 3ターゲット（`RecordoKit`、`Recordo`、`RecordoKitTests`） |
| `Makefile` | `test`、`sync`、`install-skill`、`clean` |
| `.gitignore` | ビルドの成果物を除外 |
| `AGENTS.md` | コマンド、決まりごと、設計書へのリンク（今は空のファイル） |
| `Sources/Recordo/main.swift` | `--sync-once` だけを受け付ける入口 |
| `Sources/RecordoKit/Leitner.swift` | 段と正誤から次の段と期限を返す |
| `Sources/RecordoKit/TermKey.swift` | 用語をそろえた形（`key`）にする |
| `Sources/RecordoKit/Card.swift` | `Via`、`Asked`、`Review`、`Card`、`Deck`（`cards.json` の中身）と、その更新 |
| `Sources/RecordoKit/CardStore.swift` | `cards.json` の読み書きと置き場所 |
| `Sources/RecordoKit/Distractors.swift` | 誤答の選び方 |
| `Sources/RecordoKit/HistoryReader.swift` | `history.jsonl` を読み、LLM に渡す前に落とせる行を落とす |
| `Sources/RecordoKit/TranscriptReader.swift` | セッション記録から人の入力と回答を取り出し、会話を切り出す |
| `Sources/RecordoKit/ClaudeRunner.swift` | `claude -p` の呼び出し、応答の解釈、`claude` の場所探し |
| `Sources/RecordoKit/Prompts.swift` | 判定とカード作成のプロンプト、JSON Schema、応答の型 |
| `Sources/RecordoKit/Importer.swift` | 取り込み全体の流れ |
| `skills/term/SKILL.md` | `/term` スキル。`make install-skill` で `~/.claude/skills/term` にリンクする |
| `Tests/RecordoKitTests/*.swift` | 各ファイルのテスト |

---

### Task 1: パッケージの土台と Leitner

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `.gitignore`
- Modify: `AGENTS.md`（今は空）
- Create: `Sources/Recordo/main.swift`
- Create: `Sources/RecordoKit/Leitner.swift`
- Test: `Tests/RecordoKitTests/LeitnerTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `enum Leitner { static let maxBox: Int; static func next(box: Int, correct: Bool, now: Date) -> (box: Int, due: Date) }`

- [ ] **Step 1: パッケージの設定ファイルを作る**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "recordo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Recordo", targets: ["Recordo"])
    ],
    targets: [
        .target(
            name: "RecordoKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Recordo",
            dependencies: ["RecordoKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RecordoKitTests",
            dependencies: ["RecordoKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`Makefile`（レシピの行頭はタブ文字）:

```make
.PHONY: test sync install-skill clean

test:
	swift test

# Calls the real claude -p; swift run has no bundle id, so it writes dev-cards.json.
sync:
	swift run Recordo --sync-once

install-skill:
	mkdir -p "$(HOME)/.claude/skills"
	ln -sfn "$(CURDIR)/skills/term" "$(HOME)/.claude/skills/term"

clean:
	rm -rf .build
```

`.gitignore`:

```
.build/
.swiftpm/
```

`Sources/Recordo/main.swift`（Task 9 で置き換える）:

```swift
print("usage: Recordo --sync-once")
```

`AGENTS.md`（空のファイルをこの内容にする）:

```markdown
# Recordo

Claude Code で聞いた用語を4択クイズで復習させる macOS のメニューバーアプリ。設計は `docs/superpowers/specs/2026-09-23-recordo-design.md`、実装計画は `docs/superpowers/plans/`。

## コマンド

- `make test`：`swift test`
- `make sync`：本物の `claude -p` で1回だけ取り込み、`~/Library/Application Support/Recordo/dev-cards.json` に書く
- `make install-skill`：`skills/term` を `~/.claude/skills/term` にリンクする

## 決まりごと

- SwiftPM だけで作る。Xcode のプロジェクトファイルは作らない。ロジックは `RecordoKit` に置き、`Sources/Recordo/main.swift` は入口だけにする。
- テストは XCTest。本物の `claude -p` を呼ぶテストは `CLAUDE_LIVE=1` のときだけ動く。
- テストのフィクスチャは架空の内容で作る。本物の `history.jsonl` やセッション記録の中身を貼らない。
- `claude -p` は必ず `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` と `--no-session-persistence` を付けて呼ぶ。付けないと自分のプロンプトを取り込む。
- コードのコメントは英語で2行まで。理由だけを書く。
- `public` は `RecordoKit` の外から使うものだけに付ける。
- 画面は Swift を書く前に HTML の試作を作り、承認をもらう。試作には `apple-design` スキルを使い、以前作った別のアプリの `QuizStyle.swift` とクイズの試作を土台にする。
```

- [ ] **Step 2: 失敗するテストを書く**

`Tests/RecordoKitTests/LeitnerTests.swift`:

```swift
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
```

- [ ] **Step 3: テストが失敗することを確かめる**

Run: `swift test --filter LeitnerTests`
Expected: コンパイルエラー `cannot find 'Leitner' in scope`

- [ ] **Step 4: 実装する**

`Sources/RecordoKit/Leitner.swift`:

```swift
import Foundation

enum Leitner {
    static let maxBox = 6
    static let waits: [TimeInterval] = [4 * 3600, 86400, 3 * 86400, 7 * 86400, 14 * 86400, 30 * 86400]

    static func next(box: Int, correct: Bool, now: Date) -> (box: Int, due: Date) {
        guard correct else { return (0, now) }
        let wait = waits[min(max(box, 0), waits.count - 1)]
        return (min(box + 1, maxBox), now.addingTimeInterval(wait))
    }
}
```

- [ ] **Step 5: テストが通ることを確かめる**

Run: `swift test --filter LeitnerTests`
Expected: `Executed 2 tests, with 0 failures`

Run: `swift run Recordo`
Expected: `usage: Recordo --sync-once`

- [ ] **Step 6: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: 新しいファイルが `??` で並び、`git diff --cached --stat` は何も出さない。コミットはせず、ユーザーに区切りを報告する。

---

### Task 2: カードの形、用語のそろえ方、重複の扱い

**Files:**
- Create: `Sources/RecordoKit/TermKey.swift`
- Create: `Sources/RecordoKit/Card.swift`
- Test: `Tests/RecordoKitTests/TermKeyTests.swift`
- Test: `Tests/RecordoKitTests/DeckTests.swift`

**Interfaces:**
- Consumes: `Leitner.next(box:correct:now:)`（Task 1）
- Produces:
  - `enum TermKey { static func normalize(_ term: String) -> String }`
  - `enum Via: String, Codable { case btw, term, prompt }`
  - `struct Asked: Codable, Equatable { var at: Date; var project: String; var via: Via }`
  - `struct Review: Codable, Equatable { var at: Date; var correct: Bool }`
  - `struct Card: Codable, Equatable, Identifiable { var id: UUID; var term: String; var key: String; var definition: String; var tags: [String]; var distractors: [String]; var box: Int; var due: Date; var asked: [Asked]; var reviews: [Review] }`
  - `struct Deck: Codable, Equatable { var version: Int; var importedThrough: Int; var lastSyncAt: Date?; var lastShownAt: Date?; var cards: [Card]; init(); var allTags: [String]; @discardableResult mutating func merge(term:definition:tags:distractors:asked:now:) -> Bool; mutating func answer(cardID: UUID, correct: Bool, now: Date) }`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/TermKeyTests.swift`:

```swift
import XCTest
@testable import RecordoKit

final class TermKeyTests: XCTestCase {
    func testNormalizesCaseSpacesAndQuestionSuffixes() {
        XCTAssertEqual(TermKey.normalize("  Foo-Rate "), "foo-rate")
        XCTAssertEqual(TermKey.normalize("foo-rate とは？"), "foo-rate")
        XCTAssertEqual(TermKey.normalize("Bar   Cache"), "bar cache")
        XCTAssertEqual(TermKey.normalize("bar cache って何?"), "bar cache")
        XCTAssertEqual(TermKey.normalize("BAZ\n"), "baz")
    }
}
```

`Tests/RecordoKitTests/DeckTests.swift`:

```swift
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter "TermKeyTests|DeckTests"`
Expected: コンパイルエラー `cannot find 'TermKey' in scope`、`cannot find 'Deck' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/TermKey.swift`:

```swift
import Foundation

enum TermKey {
    static let suffixes = ["とは", "って何", "?", "？"]

    static func normalize(_ term: String) -> String {
        var key = term.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        while let suffix = suffixes.first(where: { key.hasSuffix($0) }) {
            key = String(key.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return key
    }
}
```

`Sources/RecordoKit/Card.swift`:

```swift
import Foundation

enum Via: String, Codable {
    case btw, term, prompt
}

struct Asked: Codable, Equatable {
    var at: Date
    var project: String
    var via: Via
}

struct Review: Codable, Equatable {
    var at: Date
    var correct: Bool
}

struct Card: Codable, Equatable, Identifiable {
    var id: UUID
    var term: String
    var key: String
    var definition: String
    var tags: [String]
    var distractors: [String]
    var box: Int
    var due: Date
    var asked: [Asked]
    var reviews: [Review]
}

struct Deck: Codable, Equatable {
    var version = 1
    var importedThrough = 0
    var lastSyncAt: Date?
    var lastShownAt: Date?
    var cards: [Card] = []

    init() {}

    var allTags: [String] { Array(Set(cards.flatMap(\.tags))).sorted() }

    @discardableResult
    mutating func merge(term: String, definition: String, tags: [String], distractors: [String],
                        asked: Asked, now: Date) -> Bool {
        let key = TermKey.normalize(term)
        if let index = cards.firstIndex(where: { $0.key == key }) {
            // Asking again means it was forgotten, so the interval starts over.
            cards[index].asked.append(asked)
            cards[index].box = 0
            cards[index].due = now
            return false
        }
        cards.append(Card(id: UUID(), term: term, key: key, definition: definition, tags: tags,
                          distractors: distractors, box: 0, due: now, asked: [asked], reviews: []))
        return true
    }

    mutating func answer(cardID: UUID, correct: Bool, now: Date) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let next = Leitner.next(box: cards[index].box, correct: correct, now: now)
        cards[index].box = next.box
        cards[index].due = next.due
        cards[index].reviews.append(Review(at: now, correct: correct))
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter "TermKeyTests|DeckTests"`
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 3: cards.json の読み書き

**Files:**
- Create: `Sources/RecordoKit/CardStore.swift`
- Test: `Tests/RecordoKitTests/CardStoreTests.swift`

**Interfaces:**
- Consumes: `Deck`（Task 2）
- Produces:
  - `enum CardStoreError: Error { case unreadable(URL, Error) }`
  - `struct CardStore { let url: URL; init(url: URL); static var supportDirectory: URL; static func defaultURL(isDev: Bool = Bundle.main.bundleIdentifier == nil) -> URL; func load() throws -> Deck; func save(_ deck: Deck) throws }`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/CardStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter CardStoreTests`
Expected: コンパイルエラー `cannot find 'CardStore' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/CardStore.swift`:

```swift
import Foundation

enum CardStoreError: Error {
    case unreadable(URL, Error)
}

struct CardStore {
    let url: URL

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Recordo", isDirectory: true)
    }

    // swift run binaries have no bundle id, so dev runs never touch the everyday file.
    static func defaultURL(isDev: Bool = Bundle.main.bundleIdentifier == nil) -> URL {
        supportDirectory.appendingPathComponent(isDev ? "dev-cards.json" : "cards.json")
    }

    func load() throws -> Deck {
        guard FileManager.default.fileExists(atPath: url.path) else { return Deck() }
        do {
            return try Self.decoder.decode(Deck.self, from: Data(contentsOf: url))
        } catch {
            throw CardStoreError.unreadable(url, error)
        }
    }

    func save(_ deck: Deck) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(deck).write(to: url, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter CardStoreTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 4: 誤答の選び方

**Files:**
- Create: `Sources/RecordoKit/Distractors.swift`
- Test: `Tests/RecordoKitTests/DistractorsTests.swift`

**Interfaces:**
- Consumes: `Card`（Task 2）
- Produces: `enum Distractors { static func pick(for card: Card, from cards: [Card]) -> [String] }`（誤った定義を最大3つ。並び順は不定）

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/DistractorsTests.swift`:

```swift
import XCTest
@testable import RecordoKit

final class DistractorsTests: XCTestCase {
    func card(_ term: String, _ definition: String, tags: [String], backups: [String] = []) -> Card {
        Card(id: UUID(), term: term, key: TermKey.normalize(term), definition: definition, tags: tags,
             distractors: backups, box: 0, due: .distantPast, asked: [], reviews: [])
    }

    func testPrefersDefinitionsOfCardsWithTheSameTag() {
        let target = card("foo-rate", "正解", tags: ["finance"], backups: ["x", "y", "z"])
        let deck = [target,
                    card("bar-rate", "B", tags: ["finance"]),
                    card("baz-rate", "C", tags: ["finance", "web"]),
                    card("qux-rate", "D", tags: ["finance"]),
                    card("bar-cache", "E", tags: ["web"])]
        XCTAssertEqual(Set(Distractors.pick(for: target, from: deck)), ["B", "C", "D"])
    }

    func testFillsWithTheCardsOwnBackupsWhenSameTagRunsShort() {
        let target = card("foo-rate", "正解", tags: ["finance"], backups: ["x", "y", "z"])
        let deck = [target, card("bar-rate", "B", tags: ["finance"])]
        let picked = Distractors.pick(for: target, from: deck)
        XCTAssertEqual(picked.count, 3)
        XCTAssertTrue(picked.contains("B"))
        XCTAssertTrue(Set(picked).isSubset(of: ["B", "x", "y", "z"]))
    }

    func testNeverPicksTheCorrectDefinitionOrTheSameTerm() {
        let target = card("foo-rate", "正解", tags: ["finance"], backups: ["正解", "x"])
        let twin = card("Foo-Rate とは", "同じ用語の別カード", tags: ["finance"])
        let picked = Distractors.pick(for: target, from: [target, twin])
        XCTAssertEqual(picked, ["x"])
    }
}
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter DistractorsTests`
Expected: コンパイルエラー `cannot find 'Distractors' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/Distractors.swift`:

```swift
import Foundation

enum Distractors {
    // Same-tag definitions come first: unrelated ones can be ruled out by elimination.
    static func pick(for card: Card, from cards: [Card]) -> [String] {
        let tags = Set(card.tags)
        let sameTag = cards
            .filter { $0.key != card.key && !tags.isDisjoint(with: $0.tags) }
            .map(\.definition)
            .shuffled()
        var picked: [String] = []
        for text in sameTag + card.distractors.shuffled() where picked.count < 3 {
            if text != card.definition && !picked.contains(text) { picked.append(text) }
        }
        return picked
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter DistractorsTests`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 5: history.jsonl の読み込み

**Files:**
- Create: `Sources/RecordoKit/HistoryReader.swift`
- Test: `Tests/RecordoKitTests/HistoryReaderTests.swift`

**Interfaces:**
- Consumes: `Via`（Task 2）
- Produces:
  - `struct HistoryEntry: Equatable { let display: String; let timestamp: Int; let project: String; let sessionId: String; var via: Via; var body: String; var projectName: String }`
  - `enum HistoryReader { static func entries(fromJSONL text: String, after cursor: Int) -> [HistoryEntry] }`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/HistoryReaderTests.swift`:

```swift
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter HistoryReaderTests`
Expected: コンパイルエラー `cannot find 'HistoryReader' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/HistoryReader.swift`:

```swift
import Foundation

struct HistoryEntry: Equatable {
    let display: String
    let timestamp: Int
    let project: String
    let sessionId: String

    var via: Via {
        if display.hasPrefix("/btw ") { return .btw }
        if display.hasPrefix("/term ") { return .term }
        return .prompt
    }

    var body: String {
        let prefixLength = via == .btw ? 5 : via == .term ? 6 : 0
        return String(display.dropFirst(prefixLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var projectName: String { (project as NSString).lastPathComponent }
}

enum HistoryReader {
    static let maxLength = 500

    static func entries(fromJSONL text: String, after cursor: Int) -> [HistoryEntry] {
        text.split(separator: "\n").compactMap { line in
            guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)),
                  raw.timestamp > cursor else { return nil }
            let entry = HistoryEntry(display: raw.display, timestamp: raw.timestamp,
                                     project: raw.project ?? "", sessionId: raw.sessionId ?? "")
            return keeps(entry) ? entry : nil
        }
    }

    static func keeps(_ entry: HistoryEntry) -> Bool {
        let text = entry.display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxLength, !entry.sessionId.isEmpty else { return false }
        // Other slash commands (/clear, /model, ...) never ask what a word means.
        if text.hasPrefix("/") { return entry.via != .prompt && !entry.body.isEmpty }
        return true
    }

    private struct Raw: Decodable {
        let display: String
        let timestamp: Int
        let project: String?
        let sessionId: String?
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter HistoryReaderTests`
Expected: `Executed 1 test, with 0 failures`

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 6: セッション記録からの会話の切り出し

**Files:**
- Create: `Sources/RecordoKit/TranscriptReader.swift`
- Test: `Tests/RecordoKitTests/TranscriptReaderTests.swift`

**Interfaces:**
- Consumes: `HistoryEntry`、`Via`（Task 2、Task 5）
- Produces:
  - `struct Turn: Equatable { enum Role { case human, assistant }; let role: Role; let text: String; let time: Int }`（`time` はミリ秒）
  - `enum TranscriptReader { static func url(sessionId: String, projectsDir: URL) -> URL?; static func turns(fromJSONL text: String) -> [Turn]; static func context(for entry: HistoryEntry, term: String, turns: [Turn]) -> String? }`

背景：セッション記録の `type: "user"` の行にはツールの実行結果も入っている。人の入力は `promptSource` が `"typed"` か `"queued"` の行と、`promptSource` がなく本文が `<command-message>` で始まる行（`/term` などのスラッシュコマンド。直後のスキル本文の行は使わない）。assistant の行は `text` の部分だけを使い、`thinking` と `tool_use` は捨てる。`isSidechain: true`（サブエージェントの記録）は使わない。普段のプロンプトは、時刻の差が5秒以内で最も近い人の入力をその質問とみなす（セッション記録の方が数ミリ秒あとに書かれるので、「以前」で探すと1つ前の質問に当たる）。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/TranscriptReaderTests.swift`:

```swift
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter TranscriptReaderTests`
Expected: コンパイルエラー `cannot find 'TranscriptReader' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/TranscriptReader.swift`:

```swift
import Foundation

struct Turn: Equatable {
    enum Role { case human, assistant }
    let role: Role
    let text: String
    let time: Int
}

enum TranscriptReader {
    static let anchorWindow = 5_000
    static let limit = 6_000

    static func url(sessionId: String, projectsDir: URL) -> URL? {
        let folders = (try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        return folders.lazy
            .map { $0.appendingPathComponent("\(sessionId).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func turns(fromJSONL text: String) -> [Turn] {
        text.split(separator: "\n").compactMap { line in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  object["isSidechain"] as? Bool != true,
                  let stamp = object["timestamp"] as? String,
                  let time = milliseconds(stamp),
                  let message = object["message"] as? [String: Any],
                  let text = plainText(message["content"]) else { return nil }
            switch object["type"] as? String {
            case "user":
                // Tool results and skill bodies are "user" rows too; slash commands like /term carry no promptSource.
                let source = object["promptSource"] as? String
                let isCommand = source == nil && text.hasPrefix("<command-message>")
                return source == "typed" || source == "queued" || isCommand ? Turn(role: .human, text: text, time: time) : nil
            case "assistant":
                return Turn(role: .assistant, text: text, time: time)
            default:
                return nil
            }
        }
    }

    static func context(for entry: HistoryEntry, term: String, turns: [Turn]) -> String? {
        entry.via == .btw ? beforeBtw(entry, term: term, turns: turns) : replyAfter(entry, turns: turns)
    }

    // A /btw answer is never saved, so the nearest earlier turn that mentions the term stands in for it.
    static func beforeBtw(_ entry: HistoryEntry, term: String, turns: [Turn]) -> String? {
        let earlier = turns.filter { $0.time < entry.timestamp }
        guard !earlier.isEmpty else { return nil }
        let needle = term.lowercased()
        if let hit = earlier.lastIndex(where: { $0.text.lowercased().contains(needle) }) {
            let window = earlier[max(hit - 1, 0)...min(hit + 1, earlier.count - 1)]
            return String(render(window).prefix(limit))
        }
        return String(render(earlier).suffix(limit))
    }

    static func replyAfter(_ entry: HistoryEntry, turns: [Turn]) -> String? {
        let distance = { (index: Int) in abs(turns[index].time - entry.timestamp) }
        guard let anchor = turns.indices
            .filter({ turns[$0].role == .human && distance($0) <= anchorWindow })
            .min(by: { distance($0) < distance($1) }) else { return nil }
        let reply = turns[(anchor + 1)...].prefix { $0.role == .assistant }
        guard !reply.isEmpty else { return nil }
        return String(reply.map(\.text).joined(separator: "\n").prefix(limit))
    }

    static func render<C: Collection>(_ turns: C) -> String where C.Element == Turn {
        turns.map { "[\($0.role == .human ? "user" : "assistant")] \($0.text)" }.joined(separator: "\n")
    }

    static func plainText(_ content: Any?) -> String? {
        if let string = content as? String { return string.isEmpty ? nil : string }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func milliseconds(_ iso: String) -> Int? {
        formatter.date(from: iso).map { Int(($0.timeIntervalSince1970 * 1000).rounded()) }
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter TranscriptReaderTests`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 5: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 7: claude -p の呼び出し

**Files:**
- Create: `Sources/RecordoKit/ClaudeRunner.swift`
- Test: `Tests/RecordoKitTests/ClaudeRunnerTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `protocol ClaudeRunning { func run(prompt: String, schema: String) async throws -> Data }`（`structured_output` の JSON を返す）
  - `enum ClaudeError: Error, Equatable { case notFound, notLoggedIn, failed(String), badResponse }`
  - `struct ClaudeRunner: ClaudeRunning { init(executable: URL, workDir: URL, model: String = "sonnet"); static func arguments(prompt:schema:model:) -> [String]; static func environment(_ base: [String: String]) -> [String: String]; static func parse(_ output: Data) throws -> Data }`
  - `enum ClaudePath { static func resolve(override: String?, lookup: () -> String?) -> URL?; static func loginShellLookup() -> String? }`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/ClaudeRunnerTests.swift`:

```swift
import XCTest
@testable import RecordoKit

final class ClaudeRunnerTests: XCTestCase {
    func json(_ data: Data) -> NSDictionary? {
        try? JSONSerialization.jsonObject(with: data) as? NSDictionary
    }

    func testParseReturnsTheStructuredOutput() throws {
        let output = Data(#"{"type":"result","is_error":false,"result":"","structured_output":{"ok":true}}"#.utf8)
        XCTAssertEqual(json(try ClaudeRunner.parse(output)), ["ok": true])
    }

    func testParseRecognisesALoggedOutCli() {
        let output = Data(#"{"is_error":true,"result":"Not logged in · Please run /login"}"#.utf8)
        XCTAssertThrowsError(try ClaudeRunner.parse(output)) { XCTAssertEqual($0 as? ClaudeError, .notLoggedIn) }
    }

    func testParseReportsOtherErrors() {
        let output = Data(#"{"is_error":true,"result":"boom"}"#.utf8)
        XCTAssertThrowsError(try ClaudeRunner.parse(output)) { XCTAssertEqual($0 as? ClaudeError, .failed("boom")) }
    }

    func testParseRejectsMissingOrBrokenOutput() {
        for raw in [#"{"is_error":false,"result":"hi"}"#, "not json", ""] {
            XCTAssertThrowsError(try ClaudeRunner.parse(Data(raw.utf8))) {
                XCTAssertEqual($0 as? ClaudeError, .badResponse, raw)
            }
        }
    }

    func testEveryCallSkipsHistoryAndLoadsNothingExtra() {
        let arguments = ClaudeRunner.arguments(prompt: "P", schema: "{}", model: "sonnet")
        XCTAssertEqual(arguments.first, "-p")
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        let tools = try! XCTUnwrap(arguments.firstIndex(of: "--tools"))
        XCTAssertEqual(arguments[tools + 1], "")
        XCTAssertEqual(arguments.last, "P")
        XCTAssertEqual(ClaudeRunner.environment(["HOME": "/x"])["CLAUDE_CODE_SKIP_PROMPT_HISTORY"], "1")
        XCTAssertEqual(ClaudeRunner.environment(["HOME": "/x"])["HOME"], "/x")
    }

    func testResolvePrefersTheOverrideThenTheLookup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tool = dir.appendingPathComponent("claude")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        XCTAssertEqual(ClaudePath.resolve(override: tool.path, lookup: { nil })?.path, tool.path)
        XCTAssertEqual(ClaudePath.resolve(override: nil, lookup: { "noise from zshrc\n" + tool.path })?.path, tool.path)
        XCTAssertEqual(ClaudePath.resolve(override: "", lookup: { tool.path + "\n" })?.path, tool.path)
        XCTAssertNil(ClaudePath.resolve(override: nil, lookup: { nil }))
        XCTAssertNil(ClaudePath.resolve(override: dir.appendingPathComponent("missing").path, lookup: { tool.path }))
    }

    func testLiveRunReturnsStructuredOutput() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLAUDE_LIVE"] == "1", "set CLAUDE_LIVE=1 to call the real claude")
        let path = try XCTUnwrap(ClaudePath.resolve(override: nil, lookup: ClaudePath.loginShellLookup))
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runner = ClaudeRunner(executable: path, workDir: workDir)
        let schema = #"{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]}"#
        let data = try await runner.run(prompt: "Return ok=true.", schema: schema)
        XCTAssertEqual(json(data), ["ok": true])
    }
}
```

`.zshrc` が何か出力しても、ルックアップ結果は最後の行だけを使うので `claude` の場所が取れる。上書き指定（`override`）が実行できないパスなら、ルックアップに逃げずに `nil` を返す。設定の誤りを黙って別の `claude` で隠さないため。

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter ClaudeRunnerTests`
Expected: コンパイルエラー `cannot find 'ClaudeRunner' in scope`

- [ ] **Step 3: 実装する**

`Sources/RecordoKit/ClaudeRunner.swift`:

```swift
import Foundation

protocol ClaudeRunning {
    func run(prompt: String, schema: String) async throws -> Data
}

enum ClaudeError: Error, Equatable {
    case notFound
    case notLoggedIn
    case failed(String)
    case badResponse
}

struct ClaudeRunner: ClaudeRunning {
    let executable: URL
    let workDir: URL
    var model = "sonnet"

    func run(prompt: String, schema: String) async throws -> Data {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = workDir
        process.arguments = Self.arguments(prompt: prompt, schema: schema, model: model)
        process.environment = Self.environment(ProcessInfo.processInfo.environment)
        // Without a closed stdin, claude -p waits 3s for piped input on every call.
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(with: Result { try Self.parse(data) })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func arguments(prompt: String, schema: String, model: String) -> [String] {
        [
            "-p", "--no-session-persistence",
            "--settings", #"{"disableAllHooks": true}"#,
            "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
            "--tools", "",
            "--model", model,
            "--output-format", "json",
            "--json-schema", schema,
            prompt,
        ]
    }

    // Without this, Recordo's own prompts land in history.jsonl and get imported on the next sync.
    static func environment(_ base: [String: String]) -> [String: String] {
        base.merging(["CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1"]) { _, new in new }
    }

    static func parse(_ output: Data) throws -> Data {
        guard let object = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any] else {
            throw ClaudeError.badResponse
        }
        if object["is_error"] as? Bool == true {
            let message = object["result"] as? String ?? ""
            throw message.contains("Not logged in") ? ClaudeError.notLoggedIn : ClaudeError.failed(message)
        }
        guard let structured = object["structured_output"], JSONSerialization.isValidJSONObject(structured) else {
            throw ClaudeError.badResponse
        }
        return try JSONSerialization.data(withJSONObject: structured)
    }
}

enum ClaudePath {
    static func resolve(override: String?, lookup: () -> String?) -> URL? {
        let candidate = override?.isEmpty == false ? override : lookup()?.split(separator: "\n").last.map(String.init)
        guard let path = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // Finder-launched apps miss nvm's PATH; an interactive login zsh reads .zshrc, where nvm is set up.
    static func loginShellLookup() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "command -v claude"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter ClaudeRunnerTests`
Expected: `Executed 7 tests, with 0 failures (1 test skipped)`

- [ ] **Step 5: 本物の claude で確かめる**

Run: `CLAUDE_LIVE=1 swift test --filter ClaudeRunnerTests/testLiveRunReturnsStructuredOutput`
Expected: `Executed 1 test, with 0 failures`。サブスクリプションの利用枠を少し使う。

Run: `wc -l ~/.claude/history.jsonl` をこのテストの前後で実行する
Expected: 行数が変わらない（Recordo のプロンプトが履歴に入っていない）

- [ ] **Step 6: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 8: 取り込みの流れ

**Files:**
- Create: `Sources/RecordoKit/Prompts.swift`
- Create: `Sources/RecordoKit/Importer.swift`
- Test: `Tests/RecordoKitTests/ImporterTests.swift`

**Interfaces:**
- Consumes: `Deck.merge`、`Deck.allTags`（Task 2）、`CardStore`（Task 3）、`HistoryReader`、`HistoryEntry`（Task 5）、`TranscriptReader`（Task 6）、`ClaudeRunning`、`ClaudeRunner`、`ClaudePath`、`ClaudeError`（Task 7）
- Produces:
  - `public final class Importer { init(store:runner:historyURL:projectsDir:chunkSize:batchSize:now:); public static func live(claudePathOverride: String? = nil) throws -> Importer; @discardableResult public func sync(progress: (Int, Int) -> Void = { _, _ in }) async throws -> Int }`（戻り値は新しく作ったカードと段0に戻したカードの数。`progress` は `(今の塊, 塊の総数)`）

- [ ] **Step 1: 失敗するテストを書く**

`Tests/RecordoKitTests/ImporterTests.swift`:

```swift
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `swift test --filter ImporterTests`
Expected: コンパイルエラー `cannot find 'Importer' in scope`

- [ ] **Step 3: プロンプトと応答の型を書く**

`Sources/RecordoKit/Prompts.swift`:

```swift
import Foundation

enum Prompts {
    struct Question {
        let id: Int
        let question: String
        let context: String?
    }

    static let classifySchema = #"{"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"id":{"type":"integer"},"term":{"type":"string"}},"required":["id","term"]}}},"required":["items"]}"#

    static let generateSchema = #"{"type":"object","properties":{"cards":{"type":"array","items":{"type":"object","properties":{"id":{"type":"integer"},"skip":{"type":"boolean"},"term":{"type":"string"},"definition":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}},"distractors":{"type":"array","items":{"type":"string"}}},"required":["id","skip"]}}},"required":["cards"]}"#

    static func classify(_ questions: [(id: Int, text: String)]) -> String {
        let list = questions.map { "\($0.id): \($0.text)" }.joined(separator: "\n")
        return """
        ソフトウェアエンジニアが Claude Code に送った質問の一覧です。言葉、略語、概念の意味を聞いている質問だけを選んでください。

        選ぶ例：「immutable とは？」「what is PAR?」「LCP?」「TF change とは？」
        選ばない例：意味は分かったうえで原因ややり方を聞く質問（「LCP が悪いのはなぜ？」）、作業の依頼、翻訳の依頼、雑談
        そのプロジェクトの中でしか通じない呼び名も選ばない：人の略称やあだ名、マイルストーンや段階の番号、特定のファイル・文書・関数・変数・画面部品の名前

        選んだ質問ごとに、聞かれている用語を質問に書かれた表記のまま term に入れてください。1つの質問で複数の用語を聞いていれば、用語ごとに1件にします。該当がなければ items は空にします。

        質問一覧（id: 本文）:
        \(list)
        """
    }

    static func generate(_ questions: [Question], tags: [String]) -> String {
        let known = tags.isEmpty ? "（なし）" : tags.joined(separator: "、")
        let items = questions.map { question in
            "### id \(question.id)\n質問: \(question.question)\n会話:\n\(question.context ?? "（会話の記録なし）")"
        }.joined(separator: "\n\n")
        return """
        Claude Code で作業中に聞かれた用語の復習カードを作ります。各項目の質問と、その質問をしたときの会話を読み、次を返してください。

        - term: 用語。会話で使われていた表記にそろえる（略語は略語のまま）
        - definition: その会話の文脈での意味を日本語で60字以内。用語そのものは定義に書かない
        - tags: 分野のタグを1〜2個。既存のタグに合うものがあればそれを使う
        - distractors: 同じ分野で紛らわしいが誤っている定義を3つ。長さは definition との差を10字以内にし、少なくとも1つは definition より長くする。書き方もそろえる（長さで正解が分からないようにするため）
        - skip: 会話の記録がなく、質問文だけでは意味が1つに決まらないときは true。そのときは他の項目を省いてよい

        既存のタグ: \(known)

        \(items)
        """
    }

    struct ClassifyResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let term: String
        }
        let items: [Item]
    }

    struct GenerateResponse: Decodable {
        struct Card: Decodable {
            let id: Int
            let skip: Bool
            let term: String?
            let definition: String?
            let tags: [String]?
            let distractors: [String]?
        }
        let cards: [Card]
    }
}
```

「用語そのものは定義に書かない」は外さないこと。定義に用語が入っていると、4択の答えが見ただけで分かってしまう。

- [ ] **Step 4: 取り込みの流れを書く**

`Sources/RecordoKit/Importer.swift`:

```swift
import Foundation

public final class Importer {
    let store: CardStore
    let runner: ClaudeRunning
    let historyURL: URL
    let projectsDir: URL
    let chunkSize: Int
    let batchSize: Int
    let now: () -> Date

    static let lookback: TimeInterval = 30 * 86400

    init(store: CardStore, runner: ClaudeRunning, historyURL: URL, projectsDir: URL,
         chunkSize: Int = 200, batchSize: Int = 10, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.runner = runner
        self.historyURL = historyURL
        self.projectsDir = projectsDir
        self.chunkSize = chunkSize
        self.batchSize = batchSize
        self.now = now
    }

    public static func live(claudePathOverride: String? = nil) throws -> Importer {
        guard let claude = ClaudePath.resolve(override: claudePathOverride, lookup: ClaudePath.loginShellLookup) else {
            throw ClaudeError.notFound
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        // An empty working folder keeps any project's .mcp.json and CLAUDE.md out of the call.
        let workDir = CardStore.supportDirectory.appendingPathComponent("claude-cwd", isDirectory: true)
        return Importer(store: CardStore(url: CardStore.defaultURL()),
                        runner: ClaudeRunner(executable: claude, workDir: workDir),
                        historyURL: home.appendingPathComponent(".claude/history.jsonl"),
                        projectsDir: home.appendingPathComponent(".claude/projects", isDirectory: true))
    }

    @discardableResult
    public func sync(progress: (Int, Int) -> Void = { _, _ in }) async throws -> Int {
        var deck = try store.load()
        let started = now()
        // Transcripts older than 30 days are deleted, so older questions have nothing to define them from.
        let floor = max(deck.importedThrough, Int((started.timeIntervalSince1970 - Self.lookback) * 1000))
        let text = (try? String(contentsOf: historyURL, encoding: .utf8)) ?? ""
        let entries = HistoryReader.entries(fromJSONL: text, after: floor).sorted { $0.timestamp < $1.timestamp }
        let chunks = stride(from: 0, to: entries.count, by: chunkSize).map {
            Array(entries[$0..<min($0 + chunkSize, entries.count)])
        }
        var changed = 0
        for (index, chunk) in chunks.enumerated() {
            progress(index + 1, chunks.count)
            // Only a fully processed chunk is saved, so a failure retries from the same place next time.
            changed += try await importChunk(chunk, into: &deck, now: started)
            deck.importedThrough = chunk[chunk.count - 1].timestamp
            try store.save(deck)
        }
        deck.lastSyncAt = started
        try store.save(deck)
        return changed
    }

    func importChunk(_ chunk: [HistoryEntry], into deck: inout Deck, now: Date) async throws -> Int {
        let hits = try await findTerms(in: chunk)
        var turnsBySession: [String: [Turn]] = [:]
        var questions: [Prompts.Question] = []
        for (index, hit) in hits.enumerated() {
            if turnsBySession[hit.entry.sessionId] == nil {
                let url = TranscriptReader.url(sessionId: hit.entry.sessionId, projectsDir: projectsDir)
                let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
                turnsBySession[hit.entry.sessionId] = TranscriptReader.turns(fromJSONL: text)
            }
            let context = TranscriptReader.context(for: hit.entry, term: hit.term,
                                                   turns: turnsBySession[hit.entry.sessionId] ?? [])
            questions.append(Prompts.Question(id: index, question: hit.entry.body, context: context))
        }

        var changed = 0
        for start in stride(from: 0, to: questions.count, by: batchSize) {
            let batch = Array(questions[start..<min(start + batchSize, questions.count)])
            let data = try await runner.run(prompt: Prompts.generate(batch, tags: deck.allTags),
                                            schema: Prompts.generateSchema)
            for card in try decode(Prompts.GenerateResponse.self, data).cards {
                guard !card.skip, batch.contains(where: { $0.id == card.id }),
                      let term = card.term, !term.isEmpty,
                      let definition = card.definition, !definition.isEmpty else { continue }
                let entry = hits[card.id].entry
                let asked = Asked(at: Date(timeIntervalSince1970: Double(entry.timestamp) / 1000),
                                  project: entry.projectName, via: entry.via)
                deck.merge(term: term, definition: definition, tags: card.tags ?? [],
                           distractors: card.distractors ?? [], asked: asked, now: now)
                changed += 1
            }
        }
        return changed
    }

    func findTerms(in chunk: [HistoryEntry]) async throws -> [(entry: HistoryEntry, term: String)] {
        var hits = chunk.filter { $0.via == .term }.map { (entry: $0, term: $0.body) }
        let questions = chunk.enumerated().filter { $0.element.via != .term }.map { (id: $0.offset, text: $0.element.body) }
        if !questions.isEmpty {
            let data = try await runner.run(prompt: Prompts.classify(questions), schema: Prompts.classifySchema)
            for item in try decode(Prompts.ClassifyResponse.self, data).items
            where chunk.indices.contains(item.id) && chunk[item.id].via != .term && !item.term.isEmpty {
                hits.append((entry: chunk[item.id], term: item.term))
            }
        }
        return hits.sorted { $0.entry.timestamp < $1.entry.timestamp }
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ClaudeError.badResponse
        }
    }
}
```

- [ ] **Step 5: テストが通ることを確かめる**

Run: `swift test --filter ImporterTests`
Expected: `Executed 8 tests, with 0 failures`

Run: `swift test`
Expected: すべて通る（`CLAUDE_LIVE` を付けていないので本物の呼び出しは1件 skip）

- [ ] **Step 6: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、区切りを報告する。

---

### Task 9: --sync-once と /term、本物のデータでの確認

**Files:**
- Modify: `Sources/Recordo/main.swift`（全体を置き換える）
- Create: `skills/term/SKILL.md`

**Interfaces:**
- Consumes: `Importer.live(claudePathOverride:)`、`Importer.sync(progress:)`（Task 8）
- Produces: `swift run Recordo --sync-once`、`make sync`、`make install-skill`

- [ ] **Step 1: 入口を書く**

`Sources/Recordo/main.swift`:

```swift
import Foundation
import RecordoKit

// ponytail: plan 1 ships only this CLI; the menu bar app takes over this entry in plan 2.
guard CommandLine.arguments.contains("--sync-once") else {
    print("usage: Recordo --sync-once")
    exit(1)
}
do {
    let changed = try await Importer.live().sync { done, total in print("同期中 \(done)/\(total)") }
    print("\(changed) 件のカードを追加または最初の段に戻しました")
} catch {
    print("同期に失敗しました: \(error)")
    exit(1)
}
```

- [ ] **Step 2: /term スキルを書く**

`skills/term/SKILL.md`:

```markdown
---
name: term
description: Briefly explain what a term means in the current conversation. Use when the user types /term <word>. Recordo later turns these questions into review quiz cards.
---

# term

引数の用語が、今の会話の文脈で何を意味するかを説明する。

- 最初の1〜2文で定義を言い切る。120字以内を目安にする。
- 続けて、この会話のどこでどう使われていたかを1〜2文で添える。
- 略語なら正式名称も書く。
- ファイルは読み書きしない。コードも変えない。
```

- [ ] **Step 3: テストとビルドを通す**

Run: `swift test`
Expected: すべて通る

Run: `swift run Recordo`
Expected: `usage: Recordo --sync-once` と出て終了コード1

- [ ] **Step 4: 本物のデータで1回同期する**

サブスクリプションの利用枠を使う。初回は直近30日分（約3000件）を200件ずつ流すので、判定が15回前後とカード作成が数回になる。書き込み先は `dev-cards.json` で、普段使いの `cards.json` には触れない。

Run:
```bash
before=$(wc -l < ~/.claude/history.jsonl)
make sync
after=$(wc -l < ~/.claude/history.jsonl)
echo "history lines added during sync: $((after - before))"
```
Expected: `同期中 1/N` から `同期中 N/N` まで進み、`… 件のカードを追加または最初の段に戻しました` で終わる。同期の間にユーザーが Claude Code を使っていなければ、`history lines added during sync` は 0。

Run:
```bash
python3 -c '
import json, os
d = json.load(open(os.path.expanduser("~/Library/Application Support/Recordo/dev-cards.json")))
print("cards:", len(d["cards"]), "importedThrough:", d["importedThrough"], "lastSyncAt:", d["lastSyncAt"])
for c in d["cards"][:10]:
    print("-", c["term"], "|", c["tags"], "|", c["asked"][0]["via"], "|", c["definition"][:60])
'
```
Expected: 用語のカードが並ぶ。作業の依頼や翻訳の依頼がカードになっていない。定義に用語そのものが入っていない。

この出力は画面にだけ出し、ファイルや外部には送らない（プロジェクト名や作業内容が含まれるため）。結果（カード数、見てみておかしかったカードの傾向）をユーザーに報告する。

- [ ] **Step 5: 2回目の同期で重複しないことを確かめる**

Run: `make sync`
Expected: `同期中` の行が出ないか、前回以降の新しい質問の分だけ出る。カード数は、前回以降に新しく聞いた用語の分しか増えない。

- [ ] **Step 6: /term を入れて、記録のされ方を確かめる**

Run: `make install-skill && ls -l ~/.claude/skills/term`
Expected: `~/.claude/skills/term -> <このリポジトリの場所>/skills/term`

次は Claude Code の対話画面が要るので、ユーザーにお願いする：別のターミナルで Claude Code を開き、`/term foo-rate` のように架空の用語で1回使ってもらう。その後に次を実行する。

Run:
```bash
grep '"display":"/term ' ~/.claude/history.jsonl | tail -1 | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); print(d["display"][:40], d["sessionId"])'
```
Expected: `/term foo-rate` と sessionId が出る。

Run（sessionId を上の出力に置き換える）:
```bash
python3 -c '
import json, glob, os, sys
f = glob.glob(os.path.expanduser("~/.claude/projects/*/%s.jsonl" % sys.argv[1]))[0]
for line in open(f):
    e = json.loads(line)
    if e.get("type") == "user" and e.get("promptSource") in ("typed", "queued"):
        c = e["message"]["content"]
        print(e["promptSource"], e["timestamp"], repr(c if isinstance(c, str) else c)[:120])
' SESSION_ID
```
Expected: `/term` の入力が `typed` の行として記録されている。記録されていない、またはスキルの展開が別の `promptSource` で入っている場合は、設計書の「実装時に確かめること」にその結果を書き、`TranscriptReader.turns` の条件を直すかをユーザーに相談する。

- [ ] **Step 7: 区切りの確認**

Run: `git status --short && git diff --cached --stat`
Expected: `git diff --cached --stat` は何も出さない。コミットはせず、計画1の完了をユーザーに報告する。報告には、Step 4 のカード数、Step 5 の結果、Step 6 で分かった `/term` の記録のされ方を含める。

---

## 計画2に回すもの

- HTML の試作（出題の小窓、メニュー、設定）と承認。`apple-design` スキルを使う
- `QuizPanel`、出題の流れ、`Deck` からのカードの削除（「このカードを捨てる」）
- `QuizController`（60秒ごとのチェック、1日1回の同期、集中モード、静かな時間帯、全画面）
- `MenuBarExtra`、設定ウィンドウ、`Info.plist`（`LSUIElement`）と `.app` の作成
- 設計書の「実装時に確かめること」のうち、`Assertions.json` を読めるか、開発ビルドで Dock アイコンが出る件
