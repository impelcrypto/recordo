import AppKit

enum QuizGate {
    private static let syncInterval: TimeInterval = 24 * 3600
    private static let retryAfterFailure: TimeInterval = 3600

    // Without the failure wait, a logged-out claude would be retried every 60-second tick.
    static func needsSync(lastSyncAt: Date?, lastFailureAt: Date?, now: Date) -> Bool {
        if let lastFailureAt, now.timeIntervalSince(lastFailureAt) < retryAfterFailure { return false }
        guard let lastSyncAt else { return true }
        return now.timeIntervalSince(lastSyncAt) >= syncInterval
    }

    static func isTimeToAsk(lastShownAt: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let lastShownAt else { return true }
        return now.timeIntervalSince(lastShownAt) >= interval
    }

    static func inQuietHours(_ date: Date, start: Int, end: Int, calendar: Calendar = .current) -> Bool {
        guard start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    static var assertionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    // Only manually or timer-started Focus lands in this file; scheduled Focus is covered by quiet hours.
    static func focusActive(assertionsURL: URL = QuizGate.assertionsURL) -> Bool {
        guard let data = try? Data(contentsOf: assertionsURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let first = (root["data"] as? [[String: Any]])?.first,
              let records = first["storeAssertionRecords"] as? [Any] else { return false }
        return !records.isEmpty
    }

    // macOS gates this file behind Full Disk Access; without it focusActive can only ever say false.
    static func canReadFocus(assertionsURL: URL = QuizGate.assertionsURL) -> Bool {
        (try? Data(contentsOf: assertionsURL)) != nil
    }

    static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    // ponytail: window-size heuristic; full-screen has no public API for other apps.
    static func frontmostIsFullScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        for window in info where (window[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let size = CGSize(width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if screenSizes.contains(where: { abs($0.width - size.width) < 2 && abs($0.height - size.height) < 2 }) {
                return true
            }
        }
        return false
    }
}
