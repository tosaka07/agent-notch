import Foundation

/// Claude Code / Codex 共通のパーミッションモード。
///
/// Claude Code は全 hook イベント共通フィールド `permission_mode` として送ってくる
/// （`docs/data-and-display-spec.md` 参照）。Codex は `approval_policy` から同等の値に正規化する想定。
/// UI 側では agent 非依存に扱えるよう `UnifiedSession.permissionMode` として保持する。
public enum PermissionMode: String, Codable, Sendable {
    case `default`
    case acceptEdits
    case plan
    case dontAsk
    case bypassPermissions
}
