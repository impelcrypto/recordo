import Foundation

protocol ClaudeRunning {
    func run(prompt: String, schema: String) async throws -> Data
}

enum ClaudeError: Error, Equatable {
    case notFound
    case notLoggedIn
    case failed(String)
    case badResponse
}

struct ClaudeRunner: ClaudeRunning {
    let executable: URL
    let workDir: URL
    private let model = "sonnet"

    func run(prompt: String, schema: String) async throws -> Data {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = workDir
        process.arguments = Self.arguments(prompt: prompt, schema: schema, model: model)
        process.environment = Self.environment(ProcessInfo.processInfo.environment)
        // Without a closed stdin, claude -p waits 3s for piped input on every call.
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(with: Result { try Self.parse(data) })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func arguments(prompt: String, schema: String, model: String) -> [String] {
        [
            "-p", "--no-session-persistence",
            "--settings", #"{"disableAllHooks": true}"#,
            "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
            "--tools", "",
            "--model", model,
            "--output-format", "json",
            "--json-schema", schema,
            prompt,
        ]
    }

    // Without this, Recordo's own prompts land in history.jsonl and get imported on the next sync.
    static func environment(_ base: [String: String]) -> [String: String] {
        base.merging(["CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1"]) { _, new in new }
    }

    static func parse(_ output: Data) throws -> Data {
        guard let object = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any] else {
            throw ClaudeError.badResponse
        }
        if object["is_error"] as? Bool == true {
            let message = object["result"] as? String ?? ""
            throw message.contains("Not logged in") ? ClaudeError.notLoggedIn : ClaudeError.failed(message)
        }
        guard let structured = object["structured_output"], JSONSerialization.isValidJSONObject(structured) else {
            throw ClaudeError.badResponse
        }
        return try JSONSerialization.data(withJSONObject: structured)
    }
}

enum ClaudePath {
    static func resolve(override: String?, lookup: () -> String?) -> URL? {
        let candidate = override?.isEmpty == false ? override : lookup()?.split(separator: "\n").last.map(String.init)
        guard let path = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // Finder-launched apps miss nvm's PATH; an interactive login zsh reads .zshrc, where nvm is set up.
    static func loginShellLookup() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "command -v claude"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
