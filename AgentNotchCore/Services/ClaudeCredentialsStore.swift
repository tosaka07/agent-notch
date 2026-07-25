import Foundation
#if canImport(Security)
import Security
#endif

/// Claude Code の OAuth アクセストークンを読み取る。
///
/// macOS では Keychain（service: `"Claude Code-credentials"`）に保存されるのが一般的。
/// 環境によっては `~/.claude/.credentials.json` に平文で保存される場合もあるため、
/// Keychain → ファイルの順にフォールバックする。
///
/// **読み取り専用**。書き込み/削除は一切行わない。トークン値はログに出さない。
/// 取得に失敗した場合は静かに `nil` を返す — Usage セクションが非表示になるだけで
/// 他機能には影響しない設計。
enum ClaudeCredentialsStore {
    static func loadAccessToken() -> String? {
        if let token = loadFromKeychain() { return token }
        return loadFromFile()
    }

    private static func loadFromKeychain() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return extractAccessToken(from: data)
        #else
        return nil
        #endif
    }

    private static func loadFromFile() -> String? {
        let path = NSHomeDirectory() + "/.claude/.credentials.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return extractAccessToken(from: data)
    }

    private static func extractAccessToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let oauth = json["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String {
            return token
        }
        return json["accessToken"] as? String
    }
}
