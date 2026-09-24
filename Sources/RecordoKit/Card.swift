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

    mutating func remove(cardID: UUID) {
        cards.removeAll { $0.id == cardID }
    }
}
