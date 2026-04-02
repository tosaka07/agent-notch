import Foundation

/// Scans ~/.claude/projects/ for recently active JSONL transcript files
/// and restores sessions that were started before Agent Notch launched.
enum ActiveSessionScanner {
    /// Scan for JSONL files modified within the last `recencyMinutes` and extract session info.
    static func scan(recencyMinutes: Int = 10) -> [ScannedSession] {
        let claudeProjectsDir = NSHomeDirectory() + "/.claude/projects"
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) else {
            return []
        }

        var results: [ScannedSession] = []
        let cutoff = Date().addingTimeInterval(-Double(recencyMinutes * 60))

        for projectDir in projectDirs {
            let fullDir = claudeProjectsDir + "/" + projectDir
            guard let files = try? fm.contentsOfDirectory(atPath: fullDir) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let filePath = fullDir + "/" + file
                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modDate = attrs[.modificationDate] as? Date,
                      modDate > cutoff else { continue }

                if let session = parseSessionFromJSONL(path: filePath) {
                    results.append(session)
                }
            }
        }

        return results
    }

    /// Parse the first few lines of a JSONL file to extract session metadata.
    private static func parseSessionFromJSONL(path: String) -> ScannedSession? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)

        var sessionId: String?
        var model: String?
        var cwd: String?

        // Scan first 10 lines for metadata
        for line in lines.prefix(10) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            if let sid = json["sessionId"] as? String { sessionId = sid }
            if let c = json["cwd"] as? String { cwd = c }

            // Model is nested in message.model for assistant messages
            if let message = json["message"] as? [String: Any],
               let m = message["model"] as? String {
                model = m
            }
        }

        guard let sessionId else { return nil }

        // Get cumulative token usage
        let usage = TranscriptParser.parseCumulativeUsage(at: path)

        return ScannedSession(
            sessionId: sessionId,
            model: model,
            cwd: cwd,
            transcriptPath: path,
            tokenUsage: usage
        )
    }
}

struct ScannedSession {
    let sessionId: String
    let model: String?
    let cwd: String?
    let transcriptPath: String
    let tokenUsage: TokenUsage
}
