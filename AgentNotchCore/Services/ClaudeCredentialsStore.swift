import Foundation
#if canImport(Security)
import Security
#endif

/// Claude Code の OAuth 資格情報。
///
/// トークン値は `accessToken` に保持するが、**ログには絶対に出さない**
/// （`CustomStringConvertible` も意図的に実装しない）。
public struct ClaudeCredentials: Sendable, Equatable {
    public let accessToken: String
    /// トークンの有効期限。取得元に情報が無ければ `nil`。
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// 期限切れ判定。期限不明（`nil`）の場合は期限切れとみなさない。
    /// `leeway` 分だけ早めに期限切れ扱いにして、境界での 401 を避ける。
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// Claude Code の OAuth アクセストークンを **読み取り専用** で取得する。
///
/// # なぜ Keychain を直接読まないのか（issue #35）
///
/// Claude Code は Keychain item を `/usr/bin/security add-generic-password` を
/// サブプロセス起動して作成している（本体バイナリ内に `add-generic-password` /
/// `find-generic-password` の文字列が含まれることを確認済み）。
/// その結果 item の ACL が信頼するのは **`/usr/bin/security` だけ**であり、
/// Claude Code 本体も Agent Notch も ACL には含まれない。ここから非対称性が生まれる:
///
/// - `SecItemCopyMatching` で **パスワード本体**（`kSecReturnData: true`）を読むと
///   ACL 不一致となり「別のアプリがキーチェーン項目へのアクセスを求めています」
///   ダイアログが出る。「常に許可」を選んでも許可はバイナリの署名で識別されるため、
///   `swift build` ごとに ad-hoc 署名が変わる開発ビルドでは無効化され、再度聞かれる。
///   ＝ これが「一定時間ごとに認証を求められる」原因。
/// - 同じ item を `/usr/bin/security` **サブプロセス経由**で読む場合、ACL が既に
///   `/usr/bin/security` を信頼しているためダイアログは出ない。
/// - **属性のみ**（`kSecReturnData` を付けない）の `SecItemCopyMatching` は ACL を
///   参照しないためダイアログは出ない。service 名の列挙にのみ使う。
///
/// 従って取得順は `~/.claude/.credentials.json` → `/usr/bin/security` サブプロセス。
/// **`SecItemCopyMatching` によるデータ読み出しは一切行わない。**
///
/// # `.credentials.json` を優先することの妥当性
///
/// このファイルは Claude Code 自身が mode 0600（オーナーのみ読み取り可）で書く、
/// 同一ユーザーのホーム配下の平文 JSON。Agent Notch は同じユーザー権限で動くため、
/// 読むことで新たに権限が広がることはない（既に読める情報しか読まない）。
/// 加えて本 store は **読み取りのみ**で、書き込み・削除・他プロセスへの伝播を行わず、
/// トークン値をログにも UI にも出さない。macOS では通常このファイルは存在せず
/// Keychain が正となるため、実際には多くの環境で `security` 経路が使われる。
public enum ClaudeCredentialsStore {
    /// Claude Code v2.1.51 以前の service 名。
    static let legacyServiceName = "Claude Code-credentials"
    /// v2.1.52+ は `Claude Code-credentials-<hash>` を使う。
    static let serviceNamePrefix = "Claude Code-credentials"

    /// `security` サブプロセスがハングしても呼び出し側を止めないための上限。
    private static let commandTimeout: TimeInterval = 5

    // MARK: - Public

    /// 資格情報を取得する。取得できなければ静かに `nil`。
    public static func load() -> ClaudeCredentials? {
        if let creds = loadFromFile() {
            Log.hooks.debug("Claude credentials: loaded from ~/.claude/.credentials.json")
            return creds
        }
        if let creds = loadFromSecurityCommand() {
            Log.hooks.debug("Claude credentials: loaded via /usr/bin/security")
            return creds
        }
        Log.hooks.debug("Claude credentials: not found")
        return nil
    }

    /// 後方互換用。トークン文字列のみを返す。
    public static func loadAccessToken() -> String? {
        load()?.accessToken
    }

    // MARK: - Sources

    private static func loadFromFile() -> ClaudeCredentials? {
        let path = NSHomeDirectory() + "/.claude/.credentials.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return parse(data: data)
    }

    /// `/usr/bin/security find-generic-password -w` でパスワード本体を読む。
    /// ACL が `/usr/bin/security` を信頼しているため認証ダイアログは出ない。
    private static func loadFromSecurityCommand() -> ClaudeCredentials? {
        guard let service = resolveServiceName() else { return nil }
        guard let output = runSecurity(arguments: [
            "find-generic-password",
            "-s", service,
            "-a", NSUserName(),
            "-w",
        ]) else { return nil }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return parse(data: data)
    }

    // MARK: - Service 名の解決

    /// Keychain に存在する `Claude Code-credentials*` の service 名を決める。
    ///
    /// 属性のみのクエリなので ACL を参照せず、ダイアログは出ない。
    /// 無印（`Claude Code-credentials`）があればそれを優先し、無ければ
    /// ハッシュ付きのうち **最終更新が最新のもの**を選ぶ。
    /// 複数アカウント（複数の `CLAUDE_CONFIG_DIR`）を併用している場合、
    /// 直近に使ったアカウントが選ばれる想定。厳密な突き合わせは行わない。
    static func resolveServiceName() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return nil }

        let candidates: [(service: String, modified: Date)] = items.compactMap { item in
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(serviceNamePrefix) else { return nil }
            let modified = item[kSecAttrModificationDate as String] as? Date ?? .distantPast
            return (service, modified)
        }
        guard !candidates.isEmpty else { return nil }

        if candidates.contains(where: { $0.service == legacyServiceName }) {
            return legacyServiceName
        }
        return candidates.max(by: { $0.modified < $1.modified })?.service
        #else
        return nil
        #endif
    }

    // MARK: - パース

    /// Keychain / ファイルどちらも同じ JSON 形状。
    /// `{"claudeAiOauth": {"accessToken": ..., "expiresAt": <epoch ms>}}`
    static func parse(data: Data) -> ClaudeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let container = (json["claudeAiOauth"] as? [String: Any]) ?? json
        guard let token = container["accessToken"] as? String, !token.isEmpty else { return nil }
        return ClaudeCredentials(accessToken: token, expiresAt: expiry(from: container["expiresAt"]))
    }

    /// `expiresAt` は epoch ミリ秒で入っている。秒で来た場合も許容する。
    static func expiry(from value: Any?) -> Date? {
        let raw: Double
        switch value {
        case let number as NSNumber: raw = number.doubleValue
        case let string as String:
            guard let parsed = Double(string) else { return nil }
            raw = parsed
        default: return nil
        }
        guard raw > 0 else { return nil }
        // 10^12 以上ならミリ秒（2001 年以降の秒表現と衝突しない閾値）
        let seconds = raw >= 1_000_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - サブプロセス

    /// `/usr/bin/security` を引数配列で直接起動する（シェルを経由しない）。
    /// 標準出力にはトークンが乗るため、**ログには出さない**。
    private static func runSecurity(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            Log.hooks.debug("Claude credentials: failed to launch security: \(error.localizedDescription)")
            return nil
        }

        // ハング対策。パイプが埋まるほどの出力量ではないので読み切りは終了後で足りる。
        let deadline = Date().addingTimeInterval(commandTimeout)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            Log.hooks.debug("Claude credentials: security command timed out")
            return nil
        }

        guard process.terminationStatus == 0 else {
            // 44 = item not found。それ以外も理由は出さず静かに諦める。
            Log.hooks.debug("Claude credentials: security exited with \(process.terminationStatus)")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
