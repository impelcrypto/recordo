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
                    Button(tr("閉じる", "Close"), action: onClose).buttonStyle(QuizQuietButtonStyle())
                    primary(tr("同期", "Sync"), action: onSync)
                case .nothingDue:
                    primary(tr("閉じる", "Close"), action: onClose)
                case .unreadable:
                    Button(tr("Finder で表示", "Show in Finder"), action: onReveal).buttonStyle(QuizQuietButtonStyle())
                    primary(tr("閉じる", "Close"), action: onClose)
                }
            }
        }
        .quizSurface(onSize: onSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recordo")
    }

    // Space drives the primary button here too, the same key that moves the quiz on.
    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { QuizPrimaryLabel(title: title) }
            .buttonStyle(QuizPrimaryButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
    }
}
