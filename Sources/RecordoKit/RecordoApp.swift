import AppKit
import SwiftUI

public enum RecordoMain {
    @MainActor
    public static func run(arguments: [String]) {
        if arguments.contains("--sync-once") {
            // Line buffering keeps the progress lines live when output goes to a pipe or a log.
            setvbuf(stdout, nil, _IOLBF, 0)
            Task { @MainActor in await syncOnce() }
            dispatchMain()
        }
        RecordoApp.main()
    }

    @MainActor
    private static func syncOnce() async {
        do {
            let changed = try await Importer.live().sync { done, total in print("同期中 \(done)/\(total)") }
            print("\(changed) 件のカードを追加または最初の段に戻しました")
            exit(0)
        } catch {
            print("同期に失敗しました: \(error)")
            exit(1)
        }
    }
}

private struct RecordoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(percent: model.syncPercent)
        }
        .menuBarExtraStyle(.menu)
        Settings {
            SettingsView()
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon even for `swift run`, whose binary has no Info.plist with LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        AppAppearance.current.apply()
        Task { @MainActor in
            AppModel.shared.start()
            GlobalHotkey.shared.onPress = { CardListWindow.shared.show() }
            GlobalHotkey.shared.registerStored()
            if CommandLine.arguments.contains("--quiz-now") { AppModel.shared.showNow() }
        }
    }
}

// The first sync runs about half an hour, so its progress sits beside the icon instead of only inside the menu.
private struct MenuBarLabel: View {
    let percent: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.stack")
                .accessibilityLabel(Text(verbatim: "Recordo"))
            if let percent {
                Text(verbatim: "\(percent)%")
            }
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.cardsShortcut) private var cardsShortcut = Hotkey.cardsDefault.stored
    @AppStorage(SettingsKey.language) private var language = AppLanguage.system

    var body: some View {
        // Reading the language here is what rebuilds the menu when Settings changes it.
        Group {
            Button(tr("出題", "Quiz")) { model.showNow() }
                .disabled(model.isSyncing)
            switch model.syncState {
            case let .syncing(done, total):
                Text(total > 0
                     ? tr("同期中 \(AppModel.syncPercent(done: done, total: total))%", "Syncing \(AppModel.syncPercent(done: done, total: total))%")
                     : tr("同期の準備中…", "Preparing to sync…"))
            case .idle, .failed:
                Button(tr("同期", "Sync")) { model.sync() }
                    .disabled(model.panelVisible)
            }
            if case let .failed(message) = model.syncState {
                Text(tr("⚠︎ 同期できませんでした：\(message)", "⚠︎ Sync failed: \(message)"))
            }
            // The 60-second check stops quietly on a broken file, so the menu is where it has to show.
            if model.unreadable {
                Text("⚠︎ " + cardsUnreadableMessage)
            }
            Divider()
            Text(tr("最後の同期：\(model.lastSyncText)", "Last sync: \(model.lastSyncText)"))
            Divider()
            Button(tr("カード一覧…", "Cards…")) { CardListWindow.shared.show() }
                .keyboardShortcut(Hotkey(stored: cardsShortcut)?.menuShortcut)
            Button(tr("設定…", "Settings…")) {
                // An accessory app's Settings window opens behind the frontmost app unless we activate first.
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            Button(tr("Recordo を終了", "Quit Recordo")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .environment(\.locale, language.locale)
    }
}
