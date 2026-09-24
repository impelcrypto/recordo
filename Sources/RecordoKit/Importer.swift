import Foundation

final class Importer {
    private let store: CardStore
    private let runner: ClaudeRunning
    private let historyURL: URL
    private let projectsDir: URL
    private let chunkSize: Int
    private let batchSize: Int
    private let now: () -> Date

    private static let lookback: TimeInterval = 30 * 86400

    init(store: CardStore, runner: ClaudeRunning, historyURL: URL, projectsDir: URL,
         chunkSize: Int = 200, batchSize: Int = 10, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.runner = runner
        self.historyURL = historyURL
        self.projectsDir = projectsDir
        self.chunkSize = chunkSize
        self.batchSize = batchSize
        self.now = now
    }

    static func live(claudePathOverride: String? = nil) throws -> Importer {
        guard let claude = ClaudePath.resolve(override: claudePathOverride, lookup: ClaudePath.loginShellLookup) else {
            throw ClaudeError.notFound
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        // An empty working folder keeps any project's .mcp.json and CLAUDE.md out of the call.
        let workDir = CardStore.supportDirectory.appendingPathComponent("claude-cwd", isDirectory: true)
        return Importer(store: CardStore(url: CardStore.defaultURL()),
                        runner: ClaudeRunner(executable: claude, workDir: workDir),
                        historyURL: home.appendingPathComponent(".claude/history.jsonl"),
                        projectsDir: home.appendingPathComponent(".claude/projects", isDirectory: true))
    }

    @discardableResult
    func sync(progress: (Int, Int) -> Void = { _, _ in }) async throws -> Int {
        var deck = try store.load()
        let started = now()
        // Transcripts older than 30 days are deleted, so older questions have nothing to define them from.
        let floor = max(deck.importedThrough, Int((started.timeIntervalSince1970 - Self.lookback) * 1000))
        let text = (try? String(contentsOf: historyURL, encoding: .utf8)) ?? ""
        let entries = HistoryReader.entries(fromJSONL: text, after: floor).sorted { $0.timestamp < $1.timestamp }
        let chunks = stride(from: 0, to: entries.count, by: chunkSize).map {
            Array(entries[$0..<min($0 + chunkSize, entries.count)])
        }
        var changed = 0
        for (index, chunk) in chunks.enumerated() {
            progress(index + 1, chunks.count)
            // Only a fully processed chunk is saved, so a failure retries from the same place next time.
            changed += try await importChunk(chunk, into: &deck, now: started)
            deck.importedThrough = chunk[chunk.count - 1].timestamp
            try store.save(deck)
        }
        deck.lastSyncAt = started
        try store.save(deck)
        return changed
    }

    private func importChunk(_ chunk: [HistoryEntry], into deck: inout Deck, now: Date) async throws -> Int {
        let hits = try await findTerms(in: chunk)
        var turnsBySession: [String: [Turn]] = [:]
        var questions: [Prompts.Question] = []
        for (index, hit) in hits.enumerated() {
            if turnsBySession[hit.entry.sessionId] == nil {
                let url = TranscriptReader.url(sessionId: hit.entry.sessionId, projectsDir: projectsDir)
                let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
                turnsBySession[hit.entry.sessionId] = TranscriptReader.turns(fromJSONL: text)
            }
            let context = TranscriptReader.context(for: hit.entry, term: hit.term,
                                                   turns: turnsBySession[hit.entry.sessionId] ?? [])
            questions.append(Prompts.Question(id: index, question: hit.entry.body, context: context, term: hit.term))
        }

        var changed = 0
        for start in stride(from: 0, to: questions.count, by: batchSize) {
            let batch = Array(questions[start..<min(start + batchSize, questions.count)])
            // Read per batch, so switching the language during a long sync applies from the next batch.
            let data = try await runner.run(prompt: Prompts.generate(batch, tags: deck.allTags,
                                                                     japanese: AppLanguage.current.isJapanese),
                                            schema: Prompts.generateSchema)
            for card in try decode(Prompts.GenerateResponse.self, data).cards {
                guard !card.skip, batch.contains(where: { $0.id == card.id }),
                      let term = card.term, !term.isEmpty,
                      let definition = card.definition, !definition.isEmpty else { continue }
                let entry = hits[card.id].entry
                let asked = Asked(at: Date(timeIntervalSince1970: Double(entry.timestamp) / 1000),
                                  project: entry.projectName, via: entry.via)
                deck.merge(term: term, definition: definition, tags: card.tags ?? [],
                           distractors: card.distractors ?? [], asked: asked, now: now)
                changed += 1
            }
        }
        return changed
    }

    private func findTerms(in chunk: [HistoryEntry]) async throws -> [(entry: HistoryEntry, term: String)] {
        var hits = chunk.filter { $0.via == .term }.map { (entry: $0, term: $0.body) }
        let questions = chunk.enumerated().filter { $0.element.via != .term }.map { (id: $0.offset, text: $0.element.body) }
        if !questions.isEmpty {
            let data = try await runner.run(prompt: Prompts.classify(questions), schema: Prompts.classifySchema)
            for item in try decode(Prompts.ClassifyResponse.self, data).items
            where chunk.indices.contains(item.id) && chunk[item.id].via != .term && !item.term.isEmpty {
                hits.append((entry: chunk[item.id], term: item.term))
            }
        }
        return hits.sorted { $0.entry.timestamp < $1.entry.timestamp }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ClaudeError.badResponse
        }
    }
}
