import AppKit
import SwiftUI

// Values from the approved prototype (design/sessions/quiz) and an earlier app's quiz style.
enum QuizTypography {
    static let question: CGFloat = 22
    fileprivate static let option: CGFloat = 14
    static let body: CGFloat = 13
    static let meta: CGFloat = 11
}

enum QuizStyle {
    static let width: CGFloat = 340
    static let maxHeight: CGFloat = 640
    fileprivate static let gutter: CGFloat = 20
    fileprivate static let optionMinHeight: CGFloat = 48
}

/// Damping 1 everywhere except the verdict glyph, which is the one moment that earns a bounce.
enum QuizMotion {
    fileprivate static func reveal(_ reduceMotion: Bool) -> Animation {
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
    private let scrollTarget: String?
    @ViewBuilder private let header: Header
    @ViewBuilder private let body_: Body_
    @ViewBuilder private let actions: Actions
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

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // The panel never becomes active, and the default state would draw the inactive, flat material.
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
    /// Shared by the quiz and the notices, so both enter the same way.
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
        .accessibilityLabel(tr("閉じる", "Close"))
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

struct QuizQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: QuizTypography.body))
            .foregroundStyle(isEnabled ? Theme.action : Theme.secondary)
            .opacity(isEnabled ? 1 : 0.5)
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

    static let keys = ["A", "B", "C", "D"]

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
        .accessibilityValue(isCorrect ? tr("正解", "Correct") : isWrong ? tr("選んだ回答。不正解", "Your answer. Incorrect") : "")
    }
}

private struct QuizOptionButtonStyle: ButtonStyle {
    let answered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !answered && !reduceMotion ? 0.985 : 1)
            .animation(QuizMotion.press(reduceMotion), value: configuration.isPressed)
    }
}
