import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Git info resolver")
struct GitInfoResolverTests {
    @Test("Missing working directories do not resolve")
    func missingWorkingDirectory() {
        #expect(GitInfoResolver.resolve(cwd: nil) == nil)
        #expect(GitInfoResolver.resolve(cwd: "/path/that/does/not/exist") == nil)
    }

    @Test("Ordinary repositories expose the full branch path")
    func ordinaryRepository() throws {
        let repository = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repository) }
        let gitDirectory = repository.appendingPathComponent(".git")
        try FileManager.default.createDirectory(
            at: gitDirectory,
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/feature/usage-tests\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let info = try #require(GitInfoResolver.resolve(cwd: repository.path))
        #expect(info.branch == "feature/usage-tests")
        #expect(info.originRepoName == nil)
        #expect(info.worktreeName == nil)
    }

    @Test("Detached HEAD repositories resolve without a branch")
    func detachedHead() throws {
        let repository = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repository) }
        let gitDirectory = repository.appendingPathComponent(".git")
        try FileManager.default.createDirectory(
            at: gitDirectory,
            withIntermediateDirectories: true
        )
        try "0123456789abcdef\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let info = try #require(GitInfoResolver.resolve(cwd: repository.path))
        #expect(info.branch == nil)
        #expect(info.originRepoName == nil)
        #expect(info.worktreeName == nil)
    }

    @Test("Worktrees expose their branch, origin repository, and worktree names")
    func worktree() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = root.appendingPathComponent("origin-repo")
        let worktree = root.appendingPathComponent("working-copy")
        let worktreeGitDirectory =
            repository
            .appendingPathComponent(".git/worktrees/feature-wt")
        try FileManager.default.createDirectory(
            at: worktreeGitDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: worktree,
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/feature/worktree\n".write(
            to: worktreeGitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "gitdir: \(worktreeGitDirectory.path)\n".write(
            to: worktree.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        let info = try #require(GitInfoResolver.resolve(cwd: worktree.path))
        #expect(info.branch == "feature/worktree")
        #expect(info.originRepoName == "origin-repo")
        #expect(info.worktreeName == "feature-wt")
    }

    @Test("Malformed worktree pointers do not resolve")
    func malformedWorktreePointer() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "not a gitdir pointer\n".write(
            to: directory.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        #expect(GitInfoResolver.resolve(cwd: directory.path) == nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-git-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
