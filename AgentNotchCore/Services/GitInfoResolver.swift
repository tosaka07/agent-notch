import Foundation

public struct GitInfo: Sendable {
    public let branch: String?
    /// worktree のときの元リポジトリ名（例: gitdir pointer 先の `.../my-repo/.git/worktrees/wt-1`
    /// からは `my-repo` を取り出す）。通常の repo では nil。
    public let originRepoName: String?
    /// worktree ディレクトリ名。通常の repo では nil。
    public let worktreeName: String?

    public init(branch: String?, originRepoName: String?, worktreeName: String?) {
        self.branch = branch
        self.originRepoName = originRepoName
        self.worktreeName = worktreeName
    }
}

/// 作業ディレクトリから git メタ情報（branch / origin repo / worktree name）を解決する。
///
/// - 通常の repo: `{cwd}/.git/HEAD` を読む
/// - Worktree:    `{cwd}/.git` がファイルの場合 `gitdir: ...` を追い、その先の HEAD を読む
///
/// ファイル I/O を同期的に行うため、必ず非 MainActor で呼ぶこと。
/// セッションごとに 1 度だけ解決し、結果を UnifiedSession にキャッシュする想定。
public enum GitInfoResolver {
    public static func resolve(cwd: String?) -> GitInfo? {
        guard let cwd else { return nil }
        guard let resolved = resolveGitDir(cwd: cwd) else { return nil }
        let branch = readBranch(gitDir: resolved.gitDir)
        let origin = resolved.worktreeName != nil ? extractOriginRepoName(gitDir: resolved.gitDir) : nil
        return GitInfo(
            branch: branch,
            originRepoName: origin,
            worktreeName: resolved.worktreeName
        )
    }

    // MARK: - Private

    private static func resolveGitDir(cwd: String) -> (gitDir: String, worktreeName: String?)? {
        let dotGit = (cwd as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            return (dotGit, nil)
        }
        // Worktree: .git はファイルで `gitdir: /path/to/main/.git/worktrees/wt-name` を含む
        guard let raw = try? String(contentsOfFile: dotGit, encoding: .utf8) else { return nil }
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.hasPrefix("gitdir: ") else { return nil }
        let gitDir = String(content.dropFirst("gitdir: ".count))
        let parts = (gitDir as NSString).pathComponents
        let worktreeName: String? = (parts.count >= 2 && parts[parts.count - 2] == "worktrees") ? parts.last : nil
        return (gitDir, worktreeName)
    }

    private static func readBranch(gitDir: String) -> String? {
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")
        guard let raw = try? String(contentsOfFile: headPath, encoding: .utf8) else { return nil }
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        guard content.hasPrefix(prefix) else { return nil }
        return String(content.dropFirst(prefix.count))
    }

    /// `.../original-repo/.git/worktrees/wt-name` から `original-repo` を抽出する。
    private static func extractOriginRepoName(gitDir: String) -> String? {
        let p1 = (gitDir as NSString).deletingLastPathComponent  // .../.git/worktrees
        let p2 = (p1 as NSString).deletingLastPathComponent      // .../.git
        let repoPath = (p2 as NSString).deletingLastPathComponent // ...
        let name = (repoPath as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
