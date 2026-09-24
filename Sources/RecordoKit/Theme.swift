import AppKit
import SwiftUI

// Values from an earlier app's quiz theme, so both apps read as one family.
enum Theme {
    static let window = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let inset = adaptive(light: 0xF5F5F7, dark: 0x2C2C2E)
    static let text = adaptive(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let secondary = adaptive(light: 0x68686D, dark: 0xB5B5BB)
    static let line = adaptive(light: 0xDEDEE3, dark: 0x454549)
    static let action = adaptive(light: 0x0068D9, dark: 0x0071E3)
    static let success = adaptive(light: 0x267843, dark: 0x79D794)
    static let bad = adaptive(light: 0xB3261E, dark: 0xFF746D)
    static let correctFace = adaptive(light: 0xEDF7F0, dark: 0x173C29)
    static let wrongFace = adaptive(light: 0xFFF2F1, dark: 0x482321)
    // Settings cards sit lighter than the page in both modes, as System Settings' groups do.
    static let settingsPage = adaptive(light: 0xF5F5F7, dark: 0x1C1C1E)
    static let settingsCard = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return NSColor(hex: isDark ? dark : light)
        }))
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension View {
    // Custom clickable surfaces show the pointing hand; disabled ones must not.
    func clickCursor(_ enabled: Bool = true) -> some View {
        onHover { inside in
            guard enabled else { return }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
