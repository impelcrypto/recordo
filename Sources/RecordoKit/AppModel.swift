import AppKit
import SwiftUI

enum QuizNotice: Equatable {
    case noCards
    case nothingDue(next: Date, count: Int)
    case unreadable
}

// Computed, not stored: tr() has to read the language setting on every call.
var cardsUnreadableMessage: String { tr("cards.json を読めませんでした", "Couldn’t read cards.json") }

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

    private let store = CardStore(url: CardStore.defaultURL())
    private let panel = QuizPanel()
    private var timer: Timer?
    private var lastSyncFailureAt: Date?

    var isSyncing: Bool {
        if case .syncing = syncState { return true }
        return false
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

    private func reload() {
        do {
            deck = try store.load()
            unreadable = false
        } catch {
            unreadable = true
        }
    }

    private func tick(now: Date = Date()) {
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

    // Never during a sync: the importer saves its own copy of the deck chunk by chunk and would drop the answers.
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

    // A sync saves its own copy of the deck chunk by chunk, so a removal made meanwhile would come back.
    func discard(_ id: UUID) {
        guard !unreadable, !isSyncing else { return }
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
            return (tr("まだカードがありません", "No cards yet"),
                    tr("Claude Code で用語の意味を聞くと、次の同期でカードになります。",
                       "Ask Claude Code what a term means, and it becomes a card at the next sync."))
        case let .nothingDue(next, count):
            let at = when(next, now: now, calendar: calendar)
            return (tr("今出せるカードはありません", "Nothing to review right now"),
                    tr("次は\(at) に \(count) 枚出ます。",
                       count == 1 ? "The next card is due \(at)." : "The next \(count) cards are due \(at)."))
        case .unreadable:
            return (cardsUnreadableMessage,
                    tr("ファイルを直すまで、取り込みと出題を止めています。",
                       "Syncing and quizzes are paused until the file is fixed."))
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case ClaudeError.notFound:
            return tr("claude が見つかりません。設定で場所を指定してください", "claude not found. Set its location in Settings")
        case ClaudeError.notLoggedIn: return tr("claude にログインしてください", "Log in to claude")
        case CardStoreError.unreadable: return cardsUnreadableMessage
        default: return tr("claude の応答を読めませんでした", "Couldn’t read the response from claude")
        }
    }

    static func lastSyncText(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return tr("まだ同期していません", "not yet") }
        return when(date, now: now, calendar: calendar)
    }

    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = formatter("H:mm", calendar).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return tr("今日 \(time)", "today at \(time)") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return tr("明日 \(time)", "tomorrow at \(time)")
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
