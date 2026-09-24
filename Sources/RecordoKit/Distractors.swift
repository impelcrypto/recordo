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
