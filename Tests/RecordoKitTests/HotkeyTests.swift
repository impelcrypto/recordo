import AppKit
import Carbon.HIToolbox
import XCTest
@testable import RecordoKit

final class HotkeyTests: XCTestCase {
    func testTheDefaultSurvivesAStoreRoundTripAndReadsLikeAMenu() {
        let stored = Hotkey.cardsDefault.stored
        XCTAssertEqual(Hotkey(stored: stored), Hotkey.cardsDefault)
        XCTAssertEqual(Hotkey.cardsDefault.display, "⌃⌥⌘C")
    }

    func testAnEmptyOrBrokenValueMeansNoShortcut() {
        XCTAssertNil(Hotkey(stored: ""))
        XCTAssertNil(Hotkey(stored: "8:abc:C"))
        XCTAssertNil(Hotkey(stored: "8:1835008"))
    }

    func testAShortcutNeedsCommandOptionOrControl() {
        XCTAssertNil(Hotkey(keyCode: UInt16(kVK_ANSI_C), modifiers: [], characters: "c"))
        XCTAssertNil(Hotkey(keyCode: UInt16(kVK_ANSI_C), modifiers: .shift, characters: "C"))
        XCTAssertEqual(Hotkey(keyCode: UInt16(kVK_ANSI_C), modifiers: [.option, .shift], characters: "C")?.display, "⌥⇧C")
    }

    func testKeysWithoutAVisibleCharacterGetANameAndStayOutOfTheMenu() {
        let space = Hotkey(keyCode: UInt16(kVK_Space), modifiers: .command, characters: " ")
        XCTAssertEqual(space?.display, "⌘Space")
        XCTAssertNil(space?.menuShortcut)
        XCTAssertEqual(Hotkey(keyCode: UInt16(kVK_F5), modifiers: .control, characters: "\u{F708}")?.display, "⌃F5")
    }

    func testCapsLockAndOtherFlagsAreNotKept() {
        let hotkey = Hotkey(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .capsLock, .function], characters: "k")
        XCTAssertEqual(hotkey?.modifiers, .command)
        XCTAssertNotNil(hotkey?.menuShortcut)
    }
}
