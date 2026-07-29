import Foundation

/// Permission mode shared by Claude Code and Codex.
///
/// Claude Code sends it as `permission_mode` on hook events. Codex values are normalized from
/// `approval_policy`. Stored as `UnifiedSession.permissionMode` so the UI can treat it
/// agent-agnostically.
public enum PermissionMode: String, Codable, Sendable {
    case `default`
    case acceptEdits
    case plan
    case dontAsk
    case bypassPermissions
}
