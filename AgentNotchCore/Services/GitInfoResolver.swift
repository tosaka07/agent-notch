import Foundation

public struct GitInfo: Sendable {
    public let branch: String?
    /// Origin repository name when this is a worktree (e.g. `my-repo` is extracted from the
    /// gitdir pointer `.../my-repo/.git/worktrees/wt-1`). nil for an ordinary repo.
    public let originRepoName: String?
    /// Worktree directory name. nil for an ordinary repo.
    public let worktreeName: String?

    public init(branch: String?, originRepoName: String?, worktreeName: String?) {
        self.branch = branch
        self.originRepoName = originRepoName
        self.worktreeName = worktreeName
    }
}

/// Resolves git metadata (branch / origin repo / worktree name) from a working directory.
///
/// - Ordinary repo: reads `{cwd}/.git/HEAD`.
/// - Worktree: when `{cwd}/.git` is a file, follows its `gitdir: ...` pointer and reads the HEAD there.
///
/// File I/O is synchronous, so this must always be called off the MainActor.
/// Intended to be resolved once per session, with the result cached on UnifiedSession.
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
        // Worktree: .git is a file containing `gitdir: /path/to/main/.git/worktrees/wt-name`.
        guard let raw = try? String(contentsOfFile: dotGit, encoding: .utf8) else { return nil }
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.hasPrefix("gitdir: ") else { return nil }
        let gitDir = String(content.dropFirst("gitdir: ".count))
        let parts = (gitDir as NSString).pathComponents
        let worktreeName: String? =
            (parts.count >= 2 && parts[parts.count - 2] == "worktrees") ? parts.last : nil
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

    /// Extracts `original-repo` from `.../original-repo/.git/worktrees/wt-name`.
    private static func extractOriginRepoName(gitDir: String) -> String? {
        let p1 = (gitDir as NSString).deletingLastPathComponent  // .../.git/worktrees
        let p2 = (p1 as NSString).deletingLastPathComponent  // .../.git
        let repoPath = (p2 as NSString).deletingLastPathComponent  // ...
        let name = (repoPath as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
