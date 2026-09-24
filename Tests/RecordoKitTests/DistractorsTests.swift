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
