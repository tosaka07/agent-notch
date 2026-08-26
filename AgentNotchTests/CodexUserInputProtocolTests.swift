import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Codex user-input protocol")
struct CodexUserInputProtocolTests {
    @Test("Parses App Server questions without replacing transport ids with display text")
    func parsesRequest() throws {
        let object = try #require(
            JSONSerialization.jsonObject(
                with: Data(
                    #"""
                    {
                      "id": "request-7",
                      "method": "item/tool/requestUserInput",
                      "params": {
                        "threadId": "thread-1",
                        "turnId": "turn-1",
                        "itemId": "item-1",
                        "autoResolutionMs": 45000,
                        "questions": [{
                          "id": "deployment_target",
                          "header": "Target",
                          "question": "Where should this deploy?",
                          "isOther": true,
                          "isSecret": false,
                          "options": [{
                            "label": "Staging",
                            "description": "Internal environment"
                          }]
                        }]
                      }
                    }
                    """#.utf8
                )
            ) as? [String: Any]
        )

        let request = try #require(CodexUserInputProtocol.parseRequest(object))
        #expect(request.requestId == .string("request-7"))
        #expect(request.threadId == "thread-1")
        #expect(request.autoResolutionMs == 45_000)

        let question = try #require(request.questions.first)
        #expect(question.id == "deployment_target")
        #expect(question.options.first?.label == "Staging")
        #expect(question.isOther)

        let banner = question.bannerQuestion
        #expect(banner.question == "Where should this deploy?")
        #expect(banner.responseKey == "deployment_target")
        #expect(banner.id == "deployment_target")
        #expect(banner.allowsOther)
    }

    @Test("Free-text-only secret questions remain answerable")
    func secretFreeTextQuestion() {
        let object: [String: Any] = [
            "id": 9,
            "method": CodexUserInputProtocol.requestMethod,
            "params": [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "item-1",
                "questions": [
                    [
                        "id": "token",
                        "question": "Token?",
                        "isSecret": true,
                    ]
                ],
            ],
        ]

        let request = CodexUserInputProtocol.parseRequest(object)
        let question = request?.questions.first?.bannerQuestion
        #expect(question?.options.isEmpty == true)
        #expect(question?.allowsOther == true)
        #expect(question?.isSecret == true)
        #expect(request?.autoResolutionMs == nil)
        #expect(request?.expiresAt == .distantFuture)
    }

    @Test("Response echoes integer request ids and keys answers by question id")
    func buildsResponse() throws {
        let response = CodexUserInputProtocol.response(
            requestId: .integer(42),
            answers: ["deployment_target": ["Staging"]]
        )
        #expect((response["id"] as? Int64) == 42)
        let result = try #require(response["result"] as? [String: Any])
        let answers = try #require(result["answers"] as? [String: [String: [String]]])
        #expect(answers["deployment_target"]?["answers"] == ["Staging"])
    }

    @Test("Resolved notification retains the matching typed request id")
    func parsesResolution() {
        let resolved = CodexUserInputProtocol.parseResolved([
            "method": CodexUserInputProtocol.resolvedMethod,
            "params": [
                "threadId": "thread-1",
                "requestId": 42,
            ],
        ])
        #expect(resolved?.threadId == "thread-1")
        #expect(resolved?.requestId == .integer(42))
    }

    @Test("Zero-millisecond auto resolution expires immediately and booleans stay type-safe")
    func strictTimeoutAndBooleans() {
        let receivedAt = Date(timeIntervalSince1970: 100)
        let request = CodexUserInputRequest(
            requestId: .integer(1),
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            questions: [
                .init(
                    id: "answer",
                    header: nil,
                    question: "Answer?",
                    options: [],
                    isOther: true,
                    isSecret: false
                )
            ],
            autoResolutionMs: 0,
            receivedAt: receivedAt
        )
        #expect(request.expiresAt == receivedAt)

        let malformed: [String: Any] = [
            "id": 1,
            "method": CodexUserInputProtocol.requestMethod,
            "params": [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "item-1",
                "questions": [
                    [
                        "id": "answer",
                        "question": "Answer?",
                        "isOther": 1,
                    ]
                ],
            ],
        ]
        #expect(CodexUserInputProtocol.parseRequest(malformed) == nil)
    }
}
