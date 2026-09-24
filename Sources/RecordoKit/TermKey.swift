import Foundation

enum TermKey {
    private static let suffixes = ["とは", "って何", "?", "？"]

    static func normalize(_ term: String) -> String {
        var key = term.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        while let suffix = suffixes.first(where: { key.hasSuffix($0) }) {
            key = String(key.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return key
    }
}
