import Foundation

struct Turn: Equatable {
    enum Role { case human, assistant }
    let role: Role
    let text: String
    let time: Int
}

enum TranscriptReader {
    private static let anchorWindow = 5_000
    private static let limit = 6_000

    static func url(sessionId: String, projectsDir: URL) -> URL? {
        let folders = (try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        return folders.lazy
            .map { $0.appendingPathComponent("\(sessionId).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func turns(fromJSONL text: String) -> [Turn] {
        text.split(separator: "\n").compactMap { line in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  object["isSidechain"] as? Bool != true,
                  let stamp = object["timestamp"] as? String,
                  let time = milliseconds(stamp),
                  let message = object["message"] as? [String: Any],
                  let text = plainText(message["content"]) else { return nil }
            switch object["type"] as? String {
            case "user":
                // Tool results and skill bodies are "user" rows too; slash commands like /term carry no promptSource.
                let source = object["promptSource"] as? String
                let isCommand = source == nil && text.hasPrefix("<command-message>")
                return source == "typed" || source == "queued" || isCommand ? Turn(role: .human, text: text, time: time) : nil
            case "assistant":
                return Turn(role: .assistant, text: text, time: time)
            default:
                return nil
            }
        }
    }

    static func context(for entry: HistoryEntry, term: String, turns: [Turn]) -> String? {
        entry.via == .btw ? beforeBtw(entry, term: term, turns: turns) : replyAfter(entry, turns: turns)
    }

    // A /btw answer is never saved, so the nearest earlier turn that mentions the term stands in for it.
    private static func beforeBtw(_ entry: HistoryEntry, term: String, turns: [Turn]) -> String? {
        let earlier = turns.filter { $0.time < entry.timestamp }
        guard !earlier.isEmpty else { return nil }
        let needle = term.lowercased()
        if let hit = earlier.lastIndex(where: { $0.text.lowercased().contains(needle) }) {
            // The turn before only gets what the anchor leaves, so a long one cannot push the term out.
            let after = String(render(earlier[hit...min(hit + 1, earlier.count - 1)]).prefix(limit))
            guard hit > 0, after.count < limit else { return after }
            return String(render(earlier[(hit - 1)..<hit]).suffix(limit - after.count - 1)) + "\n" + after
        }
        return String(render(earlier).suffix(limit))
    }

    private static func replyAfter(_ entry: HistoryEntry, turns: [Turn]) -> String? {
        let distance = { (index: Int) in abs(turns[index].time - entry.timestamp) }
        guard let anchor = turns.indices
            .filter({ turns[$0].role == .human && distance($0) <= anchorWindow })
            .min(by: { distance($0) < distance($1) }) else { return nil }
        let reply = turns[(anchor + 1)...].prefix { $0.role == .assistant }
        guard !reply.isEmpty else { return nil }
        return String(reply.map(\.text).joined(separator: "\n").prefix(limit))
    }

    private static func render<C: Collection>(_ turns: C) -> String where C.Element == Turn {
        turns.map { "[\($0.role == .human ? "user" : "assistant")] \($0.text)" }.joined(separator: "\n")
    }

    private static func plainText(_ content: Any?) -> String? {
        if let string = content as? String { return string.isEmpty ? nil : string }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func milliseconds(_ iso: String) -> Int? {
        formatter.date(from: iso).map { Int(($0.timeIntervalSince1970 * 1000).rounded()) }
    }
}
