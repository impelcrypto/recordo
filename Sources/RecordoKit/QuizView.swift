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
                Text(verbatim: "\(tr("復習", "Review")) \(session.index + 1)/\(session.questions.count)")
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
        .accessibilityLabel(tr("Recordo 出題", "Recordo Quiz"))
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
                Button(tr("分からない", "I don’t know")) { answer { session.dontKnow() } }
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
                    Button { next() } label: { QuizPrimaryLabel(title: session.isLast ? tr("閉じる", "Close") : tr("次へ", "Next")) }
                        .buttonStyle(QuizPrimaryButtonStyle())
                        .keyboardShortcut(.space, modifiers: [])
                        .help(tr("スペース", "Space"))
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if session.verdict == nil {
            Button(tr("後で", "Later"), action: onClose)
                .buttonStyle(QuizQuietButtonStyle())
        } else if session.discarded {
            HStack(spacing: 2) {
                Text(tr("捨てました", "Discarded"))
                    .font(.system(size: QuizTypography.body))
                    .foregroundStyle(Theme.secondary)
                Button(tr("元に戻す", "Undo")) { withAnimation(.easeOut(duration: 0.15)) { session.undo() } }
                    .buttonStyle(QuizQuietButtonStyle())
            }
            .transition(.opacity)
        } else {
            Button(tr("このカードを捨てる", "Discard This Card")) { withAnimation(.easeOut(duration: 0.15)) { session.discard() } }
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
        case .correct: (title, color, glyph) = (tr("正解", "Correct"), Theme.success, "checkmark")
        case .wrong: (title, color, glyph) = (tr("不正解", "Incorrect"), Theme.bad, "xmark")
        case .dontKnow:
            let key = QuizOptionsView.keys[min(current.correctIndex, QuizOptionsView.keys.count - 1)]
            (title, color, glyph) = (tr("正しい答えは \(key)", "The answer is \(key)"), Theme.text, nil)
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
