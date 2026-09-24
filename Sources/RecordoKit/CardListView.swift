import AppKit
import SwiftUI

/// Search, order, and paging for the card list, apart from the view so tests can reach them.
@MainActor
enum CardList {
    private static let pageSize = 100

    struct Page: Equatable {
        var index: Int
        var count: Int
        var learning: [Card]
        var learned: [Card]
    }

    static func sections(_ cards: [Card], query: String) -> (learning: [Card], learned: [Card]) {
        let query = query.trimmingCharacters(in: .whitespaces)
        let hits = query.isEmpty ? cards : cards.filter {
            $0.term.localizedCaseInsensitiveContains(query) || $0.definition.localizedCaseInsensitiveContains(query)
        }
        let sorted = hits.sorted { lastAsked($0) > lastAsked($1) }
        return (sorted.filter { $0.box < Leitner.maxBox }, sorted.filter { $0.box >= Leitner.maxBox })
    }

    // Both sections read as one list cut every pageSize cards, so a section can run across two pages.
    static func page(_ index: Int, learning: [Card], learned: [Card]) -> Page {
        let total = learning.count + learned.count
        let count = max(1, (total + pageSize - 1) / pageSize)
        let index = min(max(index, 0), count - 1)
        let start = index * pageSize
        let end = min(start + pageSize, total)
        let split = learning.count
        return Page(index: index, count: count,
                    learning: Array(learning[min(start, split)..<min(end, split)]),
                    learned: Array(learned[max(start - split, 0)..<max(end - split, 0)]))
    }

    static func dueText(_ card: Card, now: Date, calendar: Calendar = .current) -> String {
        card.due <= now
            ? tr("出題待ち", "Due now")
            : tr("次の出題 ", "Next: ") + AppModel.when(card.due, now: now, calendar: calendar)
    }

    private static func lastAsked(_ card: Card) -> Date {
        card.asked.last?.at ?? .distantPast
    }
}

/// An AppKit window rather than a SwiftUI Window scene: the global shortcut has to open it
/// from outside any view, where SwiftUI's openWindow isn't available.
@MainActor
final class CardListWindow {
    static let shared = CardListWindow()
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.title = tr("カード", "Cards")
        // An accessory app's window opens behind the frontmost app unless we activate first.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: CardListView(model: .shared))
        host.sizingOptions = .minSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 720))
        window.center()
        return window
    }
}

private struct CardListView: View {
    @ObservedObject var model: AppModel
    @AppStorage(SettingsKey.language) private var language = AppLanguage.system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var page = 0
    @State private var pending: Card?
    @FocusState private var focusedTrash: UUID?
    @FocusState private var searchFocused: Bool

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var showsList: Bool { !model.unreadable && !model.deck.cards.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.everyMinute) { context in
                        content(now: context.date, proxy: proxy)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                    .column()
                    .id(Self.topID)
                }
                // Always on: at rest it lies over the list's blank top padding, so it only shows once rows pass under it.
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Theme.window, Theme.window.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 18)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Theme.window.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .onChange(of: query) { page = 0 }
        .confirmationDialog(pending.map { tr("“\($0.term)” を捨てますか？", "Discard “\($0.term)”?") } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible,
                            presenting: pending) { card in
            Button(tr("捨てる", "Discard"), role: .destructive) { discard(card) }
            Button(tr("キャンセル", "Cancel"), role: .cancel) { focusedTrash = card.id }
        } message: { _ in
            Text(tr("段と回答の記録も消えます。元に戻せません。",
                    "Its box and answer history are deleted too. This can’t be undone."))
        }
        // tr() reads defaults, not state; a new identity redraws the words after a language change.
        .id(language)
        .environment(\.locale, language.locale)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tr("カード", "Cards"))
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.52)
                    .accessibilityAddTraits(.isHeader)
                if showsList {
                    let count = model.deck.cards.count
                    Text(tr("\(count) 枚", count == 1 ? "1 card" : "\(count) cards"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
            }
            if showsList {
                searchField.padding(.top, 12)
                if model.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        Text(tr("同期中はカードを捨てられません", "Cards can’t be discarded while syncing."))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 10)
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
        .column()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            TextField(tr("用語や定義で探す", "Search terms and definitions"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .clickCursor()
                .help(tr("検索を消す", "Clear search"))
                .accessibilityLabel(tr("検索を消す", "Clear search"))
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 4)
        .frame(minHeight: 36)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(searchFocused ? Theme.action : .clear, lineWidth: 1))
    }

    // MARK: - List

    @ViewBuilder
    private func content(now: Date, proxy: ScrollViewProxy) -> some View {
        let all = CardList.sections(model.deck.cards, query: "")
        let hits = CardList.sections(model.deck.cards, query: query)
        let shown = CardList.page(page, learning: hits.learning, learned: hits.learned)
        let showLearning = !all.learning.isEmpty
            && (!shown.learning.isEmpty || (hits.learning.isEmpty && shown.index == 0))
        let showLearned = !all.learned.isEmpty
            && (!shown.learned.isEmpty || (hits.learned.isEmpty && shown.index == shown.count - 1))

        if model.unreadable {
            let copy = AppModel.noticeCopy(.unreadable, now: now)
            CardsNotice(title: copy.title, message: copy.message)
        } else if model.deck.cards.isEmpty {
            let copy = AppModel.noticeCopy(.noCards, now: now)
            CardsNotice(title: copy.title, message: copy.message)
        } else if hits.learning.isEmpty && hits.learned.isEmpty {
            CardsNotice(title: tr("“\(query)” に合うカードはありません", "No cards match “\(query)”."),
                        action: (tr("検索を消す", "Clear search"), { query = "" }))
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showLearning {
                    SectionHead(title: tr("覚えている途中", "Learning"),
                                count: countText(hits.learning.count, of: all.learning.count))
                    rows(shown.learning, now: now)
                }
                if showLearned {
                    SectionHead(title: tr("覚えた", "Learned"),
                                count: countText(hits.learned.count, of: all.learned.count),
                                note: tr("30日ごとに出題します", "Asked again every 30 days"))
                        .padding(.top, showLearning ? 28 : 0)
                    rows(shown.learned, now: now)
                }
                if shown.count > 1 {
                    pager(shown, proxy: proxy)
                }
            }
        }
    }

    private static let topID = "top"

    private func rows(_ cards: [Card], now: Date) -> some View {
        ForEach(cards) { card in
            CardRow(card: card, now: now, canDiscard: !model.isSyncing, focus: $focusedTrash) {
                pending = card
            }
            .transition(.opacity)
        }
    }

    private func countText(_ hits: Int, of total: Int) -> String {
        searching ? "\(hits) / \(total)" : "\(total)"
    }

    private func pager(_ shown: CardList.Page, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 14) {
            Button(tr("‹ 前へ", "‹ Previous")) { go(to: shown.index - 1, proxy: proxy) }
                .disabled(shown.index == 0)
            Text("\(shown.index + 1) / \(shown.count)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .monospacedDigit()
            Button(tr("次へ ›", "Next ›")) { go(to: shown.index + 1, proxy: proxy) }
                .disabled(shown.index == shown.count - 1)
        }
        .buttonStyle(QuizQuietButtonStyle())
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // A new page replaces every row, so jumping to its top reads better than scrolling through the swap.
    private func go(to index: Int, proxy: ScrollViewProxy) {
        page = index
        proxy.scrollTo(Self.topID, anchor: .top)
    }

    private func discard(_ card: Card) {
        let hits = CardList.sections(model.deck.cards, query: query)
        let shown = CardList.page(page, learning: hits.learning, learned: hits.learned)
        let order = (shown.learning + shown.learned).map(\.id)
        let next = order.firstIndex(of: card.id).flatMap { index in
            index + 1 < order.count ? order[index + 1] : (index > 0 ? order[index - 1] : nil)
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1)) {
            model.discard(card.id)
        }
        focusedTrash = next
    }
}

// MARK: - Parts

private struct SectionHead: View {
    let title: String
    let count: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.17)
                    .accessibilityAddTraits(.isHeader)
                Text(count)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .monospacedDigit()
            }
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private struct CardRow: View {
    let card: Card
    let now: Date
    let canDiscard: Bool
    let focus: FocusState<UUID?>.Binding
    let onDiscard: () -> Void
    @State private var hovering = false

    var body: some View {
        let label = tr("\(card.term) を捨てる", "Discard \(card.term)")
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(card.term)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.16)
                    .foregroundStyle(hovering || focus.wrappedValue == card.id ? Theme.action : Theme.text)
                    .animation(.easeOut(duration: 0.12), value: hovering)
                Text(card.definition)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .padding(.top, 3)
                meta
                    .padding(.top, 6)
                Text(QuizSession.source(card.asked.last))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 1)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDiscard) {
                Image(systemName: "trash")
            }
            .buttonStyle(TrashButtonStyle())
            .focused(focus, equals: card.id)
            .disabled(!canDiscard)
            .help(label)
            .accessibilityLabel(label)
            .padding(.top, -5)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    // Due cards say so in words and weight, not only by colour.
    private var meta: Text {
        let due = Text(CardList.dueText(card, now: now))
        return (Text(QuizSession.meta(card) + " · ")
            + (card.due <= now ? due.fontWeight(.semibold).foregroundStyle(Theme.text) : due))
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
            .monospacedDigit()
    }
}

private struct CardsNotice: View {
    let title: String
    var message: String?
    var action: (label: String, run: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .lineSpacing(4)
            }
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

private struct TrashButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrashFace(configuration: configuration)
    }
}

private struct TrashFace: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(Theme.secondary)
            .frame(width: 32, height: 32)
            .background(hovering && isEnabled ? Theme.inset : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(QuizMotion.press(reduceMotion), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .clickCursor(isEnabled)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}

private extension View {
    // One reading column, as in the approved mock: at most 600pt wide with 32pt sides.
    func column() -> some View {
        frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
    }
}
