import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A global shortcut, stored in UserDefaults as "keyCode:modifiers:key"; an empty string means off.
struct Hotkey: Equatable {
    fileprivate var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags
    private var key: String

    static let cardsDefault = Hotkey(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .option, .command], key: "C")

    private init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    // At least one of ⌘ ⌥ ⌃, so ordinary typing in another app can never open Recordo.
    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) {
        let modifiers = modifiers.intersection([.command, .option, .control, .shift])
        guard !modifiers.isDisjoint(with: [.command, .option, .control]),
              let key = Self.names[Int(keyCode)] ?? characters?.uppercased(), !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: modifiers, key: key)
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let keyCode = UInt32(parts[0]), let raw = UInt(parts[1]), !parts[2].isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: raw), key: parts[2])
    }

    var stored: String { "\(keyCode):\(modifiers.rawValue):\(key)" }

    /// Modifier order follows the macOS menus: ⌃ ⌥ ⇧ ⌘.
    var display: String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }.map(\.1).joined() + key
    }

    /// Only plain letters and digits, the keys a SwiftUI menu item can show as its shortcut.
    var menuShortcut: KeyboardShortcut? {
        guard key.count == 1, let character = key.lowercased().first, character.isLetter || character.isNumber else { return nil }
        var eventModifiers: SwiftUI.EventModifiers = []
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: eventModifiers)
    }

    fileprivate var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    // Keys whose typed character is invisible or a private-use glyph.
    private static let names: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// One app-wide shortcut through Carbon, which, unlike a global NSEvent monitor, needs no Accessibility permission.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    var onPress: () -> Void = {}
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    // ponytail: a combo another app already holds fails silently; show the OSStatus in Settings if that ever bites.
    fileprivate func register(_ hotkey: Hotkey?) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let hotkey else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
                Task { @MainActor in GlobalHotkey.shared.onPress() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, EventHotKeyID(signature: 0x5243_4452, id: 1),
                            GetEventDispatcherTarget(), 0, &ref)
    }

    func registerStored() {
        register(Hotkey(stored: UserDefaults.standard.string(forKey: SettingsKey.cardsShortcut) ?? ""))
    }
}

/// Click, then press the new shortcut; Esc cancels. The old shortcut is off while recording,
/// so pressing it again records it instead of opening the window.
struct HotkeyRecorder: View {
    @Binding var stored: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(recording ? tr("キーを押してください", "Press a shortcut") : Hotkey(stored: stored)?.display ?? tr("なし", "None")) {
                recording ? stop() : start()
            }
            .monospacedDigit()
            if !stored.isEmpty && !recording {
                Button {
                    stored = ""
                    GlobalHotkey.shared.register(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .clickCursor()
                .help(tr("ショートカットを消す", "Clear Shortcut"))
                .accessibilityLabel(tr("ショートカットを消す", "Clear Shortcut"))
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        GlobalHotkey.shared.register(nil)
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let hotkey = Hotkey(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                          characters: event.charactersIgnoringModifiers) {
                stored = hotkey.stored
                stop(registering: hotkey.stored)
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop(registering value: String? = nil) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        GlobalHotkey.shared.register(Hotkey(stored: value ?? stored))
    }
}
