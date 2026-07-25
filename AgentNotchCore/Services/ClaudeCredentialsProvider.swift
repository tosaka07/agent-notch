import Foundation

/// 取得済みの Claude 資格情報をプロセス生存中キャッシュし、資格情報ソースへの
/// アクセス回数を最小化する。
///
/// # 目的（issue #35）
/// `UsageCoordinator` は 180 秒ごとに使用量を取得するため、素朴に実装すると
/// その都度 Keychain / ファイルを読むことになる。ダイアログの根本原因は
/// `ClaudeCredentialsStore` 側で解消済みだが、アクセス頻度自体を下げておくことで
/// 万一ダイアログが出る環境でも「出るのは最大 1 回」に抑えられる。
///
/// # 挙動
/// - 初回のみ実際に読み込み、以降は期限までメモリのキャッシュを返す。
/// - **一度取得に失敗したらプロセスが生きている間は再試行しない**（`hasGivenUp`）。
///   ユーザーが認証ダイアログを拒否した場合に繰り返し聞かれるのを確実に防ぐ。
///   再試行させたい場合は明示的に `reset()` を呼ぶ（設定トグルの ON 操作など）。
/// - 401 を受けたら `invalidate()` でキャッシュを捨て、次回に読み直す。
///   トークンのローテーションに追従するため、これは「諦める」扱いにはしない。
public actor ClaudeCredentialsProvider {
    public static let shared = ClaudeCredentialsProvider()

    private let loader: @Sendable () -> ClaudeCredentials?
    private var cached: ClaudeCredentials?
    private var hasGivenUp = false

    public init(loader: @escaping @Sendable () -> ClaudeCredentials? = { ClaudeCredentialsStore.load() }) {
        self.loader = loader
    }

    /// 有効なアクセストークンを返す。取得不能なら `nil`。
    public func accessToken(now: Date = Date()) -> String? {
        if let cached, !cached.isExpired(now: now) {
            return cached.accessToken
        }
        // 期限切れキャッシュは捨てる（読み直しは下の give-up 判定を通す）。
        cached = nil

        guard !hasGivenUp else { return nil }

        guard let loaded = loader() else {
            hasGivenUp = true
            Log.hooks.debug("Claude credentials: unavailable, not retrying for the rest of this process")
            return nil
        }
        cached = loaded
        return loaded.accessToken
    }

    /// 401 を受けた際に呼ぶ。キャッシュのみ破棄し、次回は読み直す。
    public func invalidate() {
        cached = nil
    }

    /// 「諦めた」状態を解除して再試行を許可する（設定で使用量表示を ON にした時など）。
    public func reset() {
        cached = nil
        hasGivenUp = false
    }

    /// テスト・診断用。
    public var isGivenUp: Bool { hasGivenUp }
}
