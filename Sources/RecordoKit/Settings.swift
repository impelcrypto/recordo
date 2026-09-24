import AppKit
import SwiftUI

enum SettingsKey {
    static let intervalHours = "quizIntervalHours"
    static let quietEnabled = "quietEnabled"
    static let quietStart = "quietStartMinutes"
    static let quietEnd = "quietEndMinutes"
    static let claudePath = "claudePath"
    static let language = "appLanguage"
    fileprivate static let appearance = "appearance"
    static let cardsShortcut = "cardsShortcut"

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            intervalHours: 3,
            quietEnabled: false,
            quietStart: 22 * 60,
            quietEnd: 9 * 60,
            cardsShortcut: Hotkey.cardsDefault.stored,
        ])
    }
}

/// Language of the app's own words and of new card definitions; existing cards stay as claude wrote them.
enum AppLanguage: String {
    case system
    case japanese = "ja"
    case english = "en"

    // Read at call time, so AppKit code and static helpers follow Settings without a SwiftUI environment.
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: SettingsKey.language) ?? "") ?? .system
    }

    var isJapanese: Bool {
        switch self {
        case .japanese: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .current
        case .japanese, .english: return Locale(identifier: rawValue)
        }
    }
}

enum AppAppearance: String {
    case system
    case light
    case dark

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "") ?? .system
    }

    // One switch on NSApp reaches the AppKit panel, its blur, the Theme colors, and the Settings window.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// ponytail: inline pairs instead of a String Catalog, which needs Bundle.module and xcodebuild; switch if a third language comes.
func tr(_ ja: String, _ en: String) -> String {
    AppLanguage.current.isJapanese ? ja : en
}

struct SettingsView: View {
    @AppStorage(SettingsKey.language) private var language = AppLanguage.system
    @State private var pane: SettingsPane? = .general

    var body: some View {
        // NavigationSplitView's floating sidebar splits the titlebar and starts the rows too high.
        HSplitView {
            List(selection: $pane) {
                Section(tr("環境設定", "Preferences")) {
                    ForEach([SettingsPane.general, .quiz, .sync]) { SidebarRow(pane: $0) }
                }
                Section(tr("システム", "System")) { SidebarRow(pane: .about) }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(SidebarMaterial())
            // HSplitView lays the first child out at its maxWidth, so only a fixed width holds.
            .frame(width: 200)
            // tr() reads defaults, not state; a new identity is what redraws the words after a language change.
            .id(language)
            Group {
                switch pane ?? .general {
                case .general: GeneralPane()
                case .quiz: QuizSettingsPane()
                case .sync: SyncPane()
                case .about: AboutPane()
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            .id(language)
        }
        .frame(minWidth: 640, minHeight: 380)
        .environment(\.locale, language.locale)
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private enum SettingsPane: String, Identifiable {
    case general, quiz, sync, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return tr("一般", "General")
        case .quiz: return tr("出題", "Quizzes")
        case .sync: return tr("同期", "Sync")
        case .about: return tr("情報", "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .quiz: return "rectangle.stack.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        case .about: return "info"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .quiz: return .blue
        case .sync: return .green
        case .about: return .blue
        }
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        // Label left only ~4pt beside a custom icon; these numbers match System Settings (6pt gap, 32pt rows).
        HStack(spacing: 6) {
            SidebarIcon(systemName: pane.symbol, color: pane.color)
            Text(pane.title)
        }
        .padding(.vertical, 2)
        .tag(pane)
    }
}

private struct GeneralPane: View {
    @AppStorage(SettingsKey.language) private var language = AppLanguage.system
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system
    @AppStorage(SettingsKey.cardsShortcut) private var cardsShortcut = Hotkey.cardsDefault.stored

    var body: some View {
        SettingsPage(title: tr("一般", "General")) {
            SettingsCard {
                SettingRow(label: tr("言語", "Language")) {
                    Picker(tr("言語", "Language"), selection: $language) {
                        Text(tr("システムに合わせる", "Match System")).tag(AppLanguage.system)
                        Text(verbatim: "日本語").tag(AppLanguage.japanese)
                        Text(verbatim: "English").tag(AppLanguage.english)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingRow(label: tr("外観", "Appearance")) {
                    Picker(tr("外観", "Appearance"), selection: $appearance) {
                        Text(tr("システム", "System")).tag(AppAppearance.system)
                        Text(tr("ライト", "Light")).tag(AppAppearance.light)
                        Text(tr("ダーク", "Dark")).tag(AppAppearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingRow(label: tr("カード一覧を開く", "Open Cards")) {
                    HotkeyRecorder(stored: $cardsShortcut)
                }
            }
        }
        .onChange(of: appearance) { _, value in value.apply() }
    }
}

private struct QuizSettingsPane: View {
    @AppStorage(SettingsKey.intervalHours) private var intervalHours = 3
    @AppStorage(SettingsKey.quietEnabled) private var quietEnabled = false
    @AppStorage(SettingsKey.quietStart) private var quietStart = 22 * 60
    @AppStorage(SettingsKey.quietEnd) private var quietEnd = 9 * 60
    @State private var focusReadable = true

    var body: some View {
        SettingsPage(title: tr("出題", "Quizzes")) {
            SettingsCard {
                SettingRow(label: tr("出題の間隔", "Quiz Interval")) {
                    Picker(tr("出題の間隔", "Quiz Interval"), selection: $intervalHours) {
                        ForEach([1, 2, 3, 4, 6], id: \.self) { hours in
                            Text(tr("\(hours) 時間", hours == 1 ? "1 hour" : "\(hours) hours")).tag(hours)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsSection(title: tr("出さないとき", "When Not to Ask")) {
                SettingsCard {
                    SettingRow(label: tr("静かな時間帯", "Quiet Hours")) {
                        HStack(spacing: 6) {
                            DatePicker(tr("開始", "Start"), selection: time($quietStart), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text(verbatim: "〜")
                            DatePicker(tr("終了", "End"), selection: time($quietEnd), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Toggle(tr("静かな時間帯", "Quiet Hours"), isOn: $quietEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    RowDivider()
                    SettingRow(label: tr("集中モード", "Focus")) {
                        HStack(spacing: 8) {
                            Circle().fill(focusReadable ? Theme.success : Theme.bad).frame(width: 7, height: 7)
                            Text(focusReadable ? tr("集中モード中は出しません", "Paused during Focus")
                                               : tr("フルディスクアクセスが必要です", "Needs Full Disk Access"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                            if !focusReadable {
                                Button(tr("システム設定を開く…", "Open System Settings…")) {
                                    NSWorkspace.shared.open(QuizGate.fullDiskAccessSettingsURL)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Polled so granting access in System Settings shows up here at once.
        .task {
            while !Task.isCancelled {
                focusReadable = QuizGate.canReadFocus()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}

private struct SyncPane: View {
    @AppStorage(SettingsKey.claudePath) private var claudePath = ""
    @ObservedObject private var model = AppModel.shared
    @State private var searched = false
    @State private var claudeFound: String?

    var body: some View {
        SettingsPage(title: tr("同期", "Sync")) {
            SettingsCard {
                SettingRow(label: tr("claude の場所", "claude Location")) {
                    TextField(tr("claude の場所", "claude Location"), text: $claudePath,
                              prompt: Text(tr("自動で探す", "Find automatically")))
                        .labelsHidden()
                        .frame(maxWidth: 260)
                }
                Text(claudeStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                RowDivider()
                SettingRow(label: tr("最後の同期", "Last Sync")) {
                    Text(model.lastSyncText)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .task(id: claudePath) {
            let override = claudePath
            claudeFound = await Task.detached {
                ClaudePath.resolve(override: override, lookup: ClaudePath.loginShellLookup)?.path
            }.value
            searched = true
        }
    }

    private var claudeStatus: String {
        guard searched else { return tr("探しています…", "Searching…") }
        guard let claudeFound else {
            return tr("見つかりません。claude の場所を入力してください", "Not found. Enter the location of claude.")
        }
        let path = (claudeFound as NSString).abbreviatingWithTildeInPath
        return tr("見つかりました：\(path)", "Found: \(path)")
    }
}

// MARK: - Parts

private struct AboutPane: View {
    // make dev runs a bare binary with no Info.plist, so there is no version to read.
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    var body: some View {
        SettingsPage(title: tr("情報", "About")) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Recordo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(version.map { tr("バージョン \($0)", "Version \($0)") } ?? tr("開発ビルド", "Development Build"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Text(tr(
                "Claude Code で聞いた用語を、4択で復習するメニューバーアプリ。",
                "A menu bar app that quizzes you, four choices at a time, on terms you asked about in Claude Code."
            ))
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button(tr("データフォルダを開く", "Open Data Folder")) {
                    // The folder only exists after the first sync or answer.
                    try? FileManager.default.createDirectory(at: CardStore.supportDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(CardStore.supportDirectory)
                }
            }
            .padding(12)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.settingsPage.ignoresSafeArea())
        .navigationTitle(title)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 2)
            content
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

private struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
    }
}

private struct SidebarIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}
