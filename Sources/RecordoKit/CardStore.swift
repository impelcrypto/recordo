import Foundation

enum CardStoreError: Error {
    case unreadable(URL, Error)
}

struct CardStore {
    let url: URL

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Recordo", isDirectory: true)
    }

    // swift run binaries have no bundle id, so dev runs never touch the everyday file.
    static func defaultURL(isDev: Bool = Bundle.main.bundleIdentifier == nil) -> URL {
        supportDirectory.appendingPathComponent(isDev ? "dev-cards.json" : "cards.json")
    }

    func load() throws -> Deck {
        guard FileManager.default.fileExists(atPath: url.path) else { return Deck() }
        do {
            return try Self.decoder.decode(Deck.self, from: Data(contentsOf: url))
        } catch {
            throw CardStoreError.unreadable(url, error)
        }
    }

    func save(_ deck: Deck) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(deck).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
