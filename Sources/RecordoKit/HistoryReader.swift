import Foundation

struct HistoryEntry: Equatable {
    let display: String
    let timestamp: Int
    let project: String
    let sessionId: String

    var via: Via {
        if display.hasPrefix("/btw ") { return .btw }
        if display.hasPrefix("/term ") { return .term }
        return .prompt
    }

    var body: String {
        let rest = via == .prompt ? Substring(display) : display.drop { $0 != " " }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var projectName: String { (project as NSString).lastPathComponent }
}

enum HistoryReader {
    private static let maxLength = 500

    static func entries(fromJSONL text: String, after cursor: Int) -> [HistoryEntry] {
        text.split(separator: "\n").compactMap { line in
            guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)),
                  raw.timestamp > cursor else { return nil }
            let entry = HistoryEntry(display: raw.display, timestamp: raw.timestamp,
                                     project: raw.project ?? "", sessionId: raw.sessionId ?? "")
            return keeps(entry) ? entry : nil
        }
    }

    private static func keeps(_ entry: HistoryEntry) -> Bool {
        let text = entry.display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxLength, !entry.sessionId.isEmpty else { return false }
        // Other slash commands (/clear, /model, ...) never ask what a word means.
        if text.hasPrefix("/") { return entry.via != .prompt && !entry.body.isEmpty }
        return true
    }

    private struct Raw: Decodable {
        let display: String
        let timestamp: Int
        let project: String?
        let sessionId: String?
    }
}
