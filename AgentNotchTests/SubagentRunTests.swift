import Foundation
import Testing
@testable import AgentNotchCore

@Suite("SubagentRun / UnifiedSession subagent tests")
struct SubagentRunTests {
    @Test("startSubagent appends a running run with hasExplicitId true when agentId given")
    func startWithExplicitId() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: "agent-1")

        #expect(session.subagents.count == 1)
        #expect(session.subagents[0].id == "agent-1")
        #expect(session.subagents[0].agentType == "Explore")
        #expect(session.subagents[0].status == .running)
        #expect(session.subagents[0].hasExplicitId == true)
        #expect(session.runningSubagentCount == 1)
    }

    @Test("startSubagent synthesizes a UUID when agentId is nil")
    func startWithoutExplicitId() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: nil)

        #expect(session.subagents.count == 1)
        #expect(session.subagents[0].hasExplicitId == false)
        #expect(UUID(uuidString: session.subagents[0].id) != nil)
    }

    @Test("stopSubagent matches by agentId first")
    func stopMatchesByAgentId() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: "agent-1")
        session.startSubagent(agentType: "Explore", agentId: "agent-2")

        let matched = session.stopSubagent(agentId: "agent-2", agentType: "Explore", transcriptPath: nil)

        #expect(matched)
        #expect(session.subagents.first(where: { $0.id == "agent-2" })?.status == .completed)
        #expect(session.subagents.first(where: { $0.id == "agent-1" })?.status == .running)
        #expect(session.runningSubagentCount == 1)
    }

    @Test("stopSubagent falls back to oldest running of same agentType when agentId is unmatched/missing")
    func stopFallsBackToAgentTypeFIFO() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        let t0 = Date()
        session.startSubagent(agentType: "Explore", agentId: nil, at: t0)
        session.startSubagent(agentType: "Explore", agentId: nil, at: t0.addingTimeInterval(1))
        session.startSubagent(agentType: "code-reviewer", agentId: nil, at: t0.addingTimeInterval(2))

        // agentId が無い Stop は agentType 一致の最古 running にマッチする
        let matched = session.stopSubagent(agentId: nil, agentType: "Explore", transcriptPath: nil)

        #expect(matched)
        let explores = session.subagents.filter { $0.agentType == "Explore" }
        #expect(explores.filter { $0.status == .completed }.count == 1)
        // 最古（t0）の方が完了しているはず
        let completedExplore = explores.first { $0.status == .completed }
        #expect(completedExplore?.startedAt == t0)
    }

    @Test("stopSubagent falls back to oldest running overall when agentId/agentType both unmatched")
    func stopFallsBackToOldestRunningOverall() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        let t0 = Date()
        session.startSubagent(agentType: "Explore", agentId: nil, at: t0)
        session.startSubagent(agentType: "code-reviewer", agentId: nil, at: t0.addingTimeInterval(1))

        // agentType が一致しない場合でも、最古の running にフォールバックする
        let matched = session.stopSubagent(agentId: "unknown-id", agentType: "unknown-type", transcriptPath: nil)

        #expect(matched)
        #expect(session.subagents.first(where: { $0.agentType == "Explore" })?.status == .completed)
        #expect(session.subagents.first(where: { $0.agentType == "code-reviewer" })?.status == .running)
    }

    @Test("Double stop with no running subagents left returns false (idempotent)")
    func doubleStopIsIgnored() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: "agent-1")

        #expect(session.stopSubagent(agentId: "agent-1", agentType: "Explore", transcriptPath: nil))
        // 2 回目の Stop はマッチする running が無いので false
        #expect(session.stopSubagent(agentId: "agent-1", agentType: "Explore", transcriptPath: nil) == false)
    }

    @Test("3 concurrent subagents can stop out of order and runningSubagentCount tracks correctly")
    func threeConcurrentOutOfOrder() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: "a")
        session.startSubagent(agentType: "code-reviewer", agentId: "b")
        session.startSubagent(agentType: "Explore", agentId: "c")

        #expect(session.runningSubagentCount == 3)

        #expect(session.stopSubagent(agentId: "c", agentType: nil, transcriptPath: nil))
        #expect(session.runningSubagentCount == 2)

        #expect(session.stopSubagent(agentId: "a", agentType: nil, transcriptPath: nil))
        #expect(session.runningSubagentCount == 1)

        #expect(session.stopSubagent(agentId: "b", agentType: nil, transcriptPath: nil))
        #expect(session.runningSubagentCount == 0)
    }

    @Test("stopSubagent records transcriptPath and endedAt")
    func stopRecordsTranscriptPath() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: "agent-1")

        _ = session.stopSubagent(agentId: "agent-1", agentType: "Explore", transcriptPath: "/tmp/t.jsonl")

        let run = session.subagents.first
        #expect(run?.transcriptPath == "/tmp/t.jsonl")
        #expect(run?.endedAt != nil)
    }

    @Test("completed subagents beyond 50 are trimmed, oldest first")
    func trimsCompletedBeyond50() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        let base = Date()

        for i in 0..<60 {
            let start = base.addingTimeInterval(TimeInterval(i))
            session.startSubagent(agentType: "Explore", agentId: "agent-\(i)", at: start)
            _ = session.stopSubagent(
                agentId: "agent-\(i)", agentType: "Explore", transcriptPath: nil,
                at: start.addingTimeInterval(0.5)
            )
        }

        #expect(session.subagents.count == 50)
        // 最も新しい (agent-59) は残り、最も古い (agent-0) は落ちている
        #expect(session.subagents.contains { $0.id == "agent-59" })
        #expect(session.subagents.contains { $0.id == "agent-0" } == false)
    }

    @Test("foldRunningSubagentsToCompleted completes all running runs")
    func foldRunningToCompleted() {
        let session = UnifiedSession(id: "s1", agentType: .claudeCode)
        session.startSubagent(agentType: "Explore", agentId: "a")
        session.startSubagent(agentType: "code-reviewer", agentId: "b")

        session.foldRunningSubagentsToCompleted()

        #expect(session.runningSubagentCount == 0)
        #expect(session.subagents.allSatisfy { $0.status == .completed })
        #expect(session.subagents.allSatisfy { $0.endedAt != nil })
    }
}
