import AppKit
import SwiftUI

/// The corner popup. Non-activating, so a quiz never takes the keyboard from the app in use.
final class QuizPanel: NSPanel {
    private var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: QuizStyle.width, height: 320),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .closable],
            backing: .buffered,
            defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func show<Content: View>(_ view: Content, onClose: @escaping () -> Void) {
        self.onClose = onClose
        // Hidden title bar means no visible text; the title still names the window for VoiceOver.
        title = tr("Recordo 出題", "Recordo Quiz")
        setAccessibilityTitle(title)
        let host = NSHostingView(rootView: view)
        // SwiftUI would resize the window top-anchored and walk it off screen; adjust(to:) owns the size.
        host.sizingOptions = []
        contentView = host
        alphaValue = 1
        if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 24, y: visible.minY + 24))
        }
        orderFrontRegardless()
    }

    override func close() {
        let callback = onClose
        onClose = nil
        callback?()
        guard isVisible else { return super.close() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.finishClose()
        })
    }

    private func finishClose() {
        super.close()
        alphaValue = 1
    }

    func adjust(to content: CGSize) {
        let inset = contentView?.safeAreaInsets.top ?? 0
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        let heightCap = min(QuizStyle.maxHeight, (visible?.height ?? QuizStyle.maxHeight) - 48)
        let target = NSSize(width: max(content.width, 280),
                            height: min(max(content.height + inset, 160), max(heightCap, 160)))
        guard abs(frame.height - target.height) > 2 || abs(frame.width - target.width) > 2 else { return }
        var origin = frame.origin
        if let visible {
            origin.x = min(origin.x, visible.maxX - target.width - 24)
            origin.y = max(origin.y, visible.minY + 24)
        }
        setFrame(NSRect(origin: origin, size: target), display: true)
    }
}
