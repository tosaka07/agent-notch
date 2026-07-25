import Foundation

/// Codex CLI の rollout jsonl（`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`）から
/// 直近の `token_count` イベントに載っている `rate_limits` を読み取る。
///
/// Codex 本体が API レスポンスヘッダー（`x-codex-primary-used-percent` 等）から得た値を
/// そのまま rollout に書き出しているため、追加の認証・API 呼び出し無しで正確な値が取れる。
/// ただし usage-based（従量課金）プランでは primary/secondary が null になる。
///
/// # パフォーマンス
/// rollout は数百 MB に膨れることがあるため、以下を徹底する:
/// - 最新ファイルの探索は `YYYY/MM/DD` の日付ディレクトリ構造を降順に辿り、最初に
///   見つかった時点で打ち切る（`sessions` 配下の全ファイル再帰スキャンはしない）。
/// - ファイル内容は全文読み込みせず、末尾の固定サイズチャンクのみ `FileHandle` で読む
///   （`token_count` イベントは末尾付近に出るため十分）。
public enum CodexUsageParser {
    /// tail read で読み込む末尾のバイト数。
    public static let defaultTailBytes = 256 * 1024

    /// `~/.codex/sessions` 配下から最新の rollout ファイルを探し、直近の rate_limits を返す。
    /// tail チャンク内に `token_count` イベントが無ければ `nil`（次回ポーリングで再試行される）。
    public static func latestSnapshot(
        sessionsDirectory: String = NSHomeDirectory() + "/.codex/sessions",
        tailBytes: Int = defaultTailBytes
    ) -> CodexUsageSnapshot? {
        guard let path = latestRolloutFile(in: sessionsDirectory) else { return nil }
        guard let content = tailContent(ofFileAt: path, maxBytes: tailBytes) else { return nil }
        return parseLatestRateLimits(fromLines: content.components(separatedBy: .newlines))
    }

    /// `sessions/YYYY/MM/DD/rollout-*.jsonl` を年→月→日の順に降順で辿り、
    /// 最初に rollout ファイルが見つかった日付ディレクトリの最新ファイルを返す。
    /// 各階層は 1 段だけ列挙するため、シンボリックリンク循環の影響を受けない。
    static func latestRolloutFile(in sessionsDirectory: String) -> String? {
        let fm = FileManager.default
        for year in sortedDescendingSubdirectories(of: sessionsDirectory, fm: fm) {
            let yearDir = sessionsDirectory + "/" + year
            for month in sortedDescendingSubdirectories(of: yearDir, fm: fm) {
                let monthDir = yearDir + "/" + month
                for day in sortedDescendingSubdirectories(of: monthDir, fm: fm) {
                    let dayDir = monthDir + "/" + day
                    if let file = latestRolloutFile(inDayDirectory: dayDir, fm: fm) {
                        return file
                    }
                }
            }
        }
        return nil
    }

    /// ディレクトリ直下のサブディレクトリ名を降順（新しい日付が先）でソートして返す。
    /// `YYYY`/`MM`/`DD` はゼロ埋め固定長のため文字列降順ソートがそのまま日付降順になる。
    private static func sortedDescendingSubdirectories(of path: String, fm: FileManager) -> [String] {
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return entries
            .filter { name in
                guard !name.hasPrefix(".") else { return false }
                var isDir: ObjCBool = false
                let full = path + "/" + name
                return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
            }
            .sorted(by: >)
    }

    /// 日付ディレクトリ内で最新（ファイル名降順で先頭）の `.jsonl` ファイルのパスを返す。
    /// rollout ファイル名にはタイムスタンプが先頭付近に入るため、文字列降順ソートで
    /// 最新ファイルが先頭に来る。
    private static func latestRolloutFile(inDayDirectory dayDir: String, fm: FileManager) -> String? {
        guard let entries = try? fm.contentsOfDirectory(atPath: dayDir) else { return nil }
        guard let latest = entries.filter({ $0.hasSuffix(".jsonl") }).sorted(by: >).first else { return nil }
        return dayDir + "/" + latest
    }

    /// ファイル末尾から最大 `maxBytes` を `FileHandle` で読み、UTF-8 文字列として返す。
    /// 不正な UTF-8 境界は置換文字になるだけでクラッシュしない（`String(decoding:as:)`）。
    /// ファイル先頭から読んだのでない限り、先頭行は途中から始まる不完全行の可能性が
    /// 高いため 1 行分捨てる。
    static func tailContent(ofFileAt path: String, maxBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }
        let readSize = min(UInt64(maxBytes), fileSize)
        let offset = fileSize - readSize
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        guard let data = try? handle.readToEnd() else { return nil }

        var content = String(decoding: data, as: UTF8.self)
        if offset > 0, let firstNewline = content.firstIndex(of: "\n") {
            content = String(content[content.index(after: firstNewline)...])
        }
        return content
    }

    /// jsonl の行配列を末尾から走査し、最初に見つかった `token_count` イベントの
    /// `rate_limits` をパースして返す。
    static func parseLatestRateLimits(fromLines lines: [String]) -> CodexUsageSnapshot? {
        for line in lines.reversed() {
            if let snapshot = parseLine(line) {
                return snapshot
            }
        }
        return nil
    }

    /// rollout jsonl の 1 行をパースする。`token_count` イベントでなければ nil。
    /// テスト用に public にしている。
    public static func parseLine(_ line: String) -> CodexUsageSnapshot? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any]
        else { return nil }
        return parse(rateLimits: rateLimits)
    }

    /// `rate_limits` オブジェクト 1 件分をパースする。テスト用に public にしている。
    public static func parse(rateLimits: [String: Any]) -> CodexUsageSnapshot? {
        let planType = rateLimits["plan_type"] as? String
        let primary = window(from: rateLimits["primary"] as? [String: Any])
        let secondary = window(from: rateLimits["secondary"] as? [String: Any])
        guard primary != nil || secondary != nil || planType != nil else { return nil }
        return CodexUsageSnapshot(primary: primary, secondary: secondary, planType: planType)
    }

    private static func window(from raw: [String: Any]?) -> UsageWindow? {
        guard let raw else { return nil }
        let percent: Double?
        if let d = raw["used_percent"] as? Double {
            percent = d
        } else if let i = raw["used_percent"] as? Int {
            percent = Double(i)
        } else {
            percent = nil
        }
        guard let percent else { return nil }

        var resetsAt: Date?
        if let epoch = raw["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let epochInt = raw["resets_at"] as? Int {
            resetsAt = Date(timeIntervalSince1970: Double(epochInt))
        }
        return UsageWindow(usedPercent: percent, resetsAt: resetsAt)
    }
}
