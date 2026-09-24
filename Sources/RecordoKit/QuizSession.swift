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

    // Discarding waits until the person moves on, so Undo works without re-inserting a card.
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
        "\(card.tags.first ?? tr("未分類", "Uncategorized")) · \(tr("段", "Box")) \(card.box)"
    }

    static func source(_ asked: Asked?) -> String {
        guard let asked else { return "" }
        let how: String
        switch asked.via {
        case .btw: how = tr("/btw で質問", "asked via /btw")
        case .term: how = tr("/term で質問", "asked via /term")
        case .prompt: how = tr("会話で質問", "asked in chat")
        }
        return "\(dayFormatter.string(from: asked.at)) · \(asked.project) · \(how)"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
}
