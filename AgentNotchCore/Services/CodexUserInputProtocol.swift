import Foundation

/// JSON-RPC request ids used by Codex App Server.
///
/// The protocol permits either string or integer ids. Keeping the original
/// representation matters because the answer must echo the exact id back to
/// App Server.
public enum CodexRPCID: Hashable, Sendable {
    case string(String)
    case integer(Int64)

    public init?(jsonValue: Any) {
        if let value = jsonValue as? String {
            self = .string(value)
            return
        }
        if let value = jsonValue as? NSNumber,
            CFGetTypeID(value) != CFBooleanGetTypeID()
        {
            self = .integer(value.int64Value)
            return
        }
        return nil
    }

    public var jsonValue: Any {
        switch self {
        case .string(let value): value
        case .integer(let value): value
        }
    }

    /// Stable, non-reversible UI key. Transport code retains the typed id and
    /// never attempts to parse this value back.
    public var displayKey: String {
        switch self {
        case .string(let value): "s:\(value)"
        case .integer(let value): "i:\(value)"
        }
    }
}

public struct CodexUserInputRequest: Sendable {
    public struct Question: Sendable, Hashable {
        public struct Option: Sendable, Hashable {
            public let label: String
            public let description: String?

            public init(label: String, description: String?) {
                self.label = label
                self.description = description
            }
        }

        public let id: String
        public let header: String?
        public let question: String
        public let options: [Option]
        public let isOther: Bool
        public let isSecret: Bool

        public init(
            id: String,
            header: String?,
            question: String,
            options: [Option],
            isOther: Bool,
            isSecret: Bool
        ) {
            self.id = id
            self.header = header
            self.question = question
            self.options = options
            self.isOther = isOther
            self.isSecret = isSecret
        }

        public var bannerQuestion: AskQuestionInfo.Question {
            AskQuestionInfo.Question(
                question: question,
                header: header,
                multiSelect: false,
                options: options.map {
                    AskQuestionInfo.Option(
                        label: $0.label,
                        description: $0.description,
                        preview: nil
                    )
                },
                responseKey: id,
                allowsOther: isOther || options.isEmpty,
                isSecret: isSecret
            )
        }
    }

    public let requestId: CodexRPCID
    public let threadId: String
    public let turnId: String
    public let itemId: String
    public let questions: [Question]
    public let autoResolutionMs: Int?
    public let receivedAt: Date

    public init(
        requestId: CodexRPCID,
        threadId: String,
        turnId: String,
        itemId: String,
        questions: [Question],
        autoResolutionMs: Int?,
        receivedAt: Date = Date()
    ) {
        self.requestId = requestId
        self.threadId = threadId
        self.turnId = turnId
        self.itemId = itemId
        self.questions = questions
        self.autoResolutionMs = autoResolutionMs
        self.receivedAt = receivedAt
    }

    public var expiresAt: Date {
        guard let autoResolutionMs else {
            return .distantFuture
        }
        return receivedAt.addingTimeInterval(TimeInterval(autoResolutionMs) / 1_000)
    }
}

public struct CodexResolvedUserInput: Sendable {
    public let requestId: CodexRPCID
    public let threadId: String

    public init(requestId: CodexRPCID, threadId: String) {
        self.requestId = requestId
        self.threadId = threadId
    }
}

/// Converts the App Server's untyped JSON envelope at one narrow boundary.
public enum CodexUserInputProtocol {
    public static let requestMethod = "item/tool/requestUserInput"
    public static let resolvedMethod = "serverRequest/resolved"

    public static func parseRequest(_ object: [String: Any]) -> CodexUserInputRequest? {
        guard object["method"] as? String == requestMethod,
            let requestId = object["id"].flatMap(CodexRPCID.init(jsonValue:)),
            let params = object["params"] as? [String: Any],
            let threadId = params["threadId"] as? String,
            let turnId = params["turnId"] as? String,
            let itemId = params["itemId"] as? String,
            let rawQuestions = params["questions"] as? [[String: Any]]
        else { return nil }

        guard let questions = parseQuestions(rawQuestions),
            let autoResolutionMs = parseAutoResolutionMs(params["autoResolutionMs"])
        else { return nil }

        return CodexUserInputRequest(
            requestId: requestId,
            threadId: threadId,
            turnId: turnId,
            itemId: itemId,
            questions: questions,
            autoResolutionMs: autoResolutionMs
        )
    }

    public static func parseResolved(_ object: [String: Any]) -> CodexResolvedUserInput? {
        guard object["method"] as? String == resolvedMethod,
            let params = object["params"] as? [String: Any],
            let threadId = params["threadId"] as? String,
            let requestId = params["requestId"].flatMap(CodexRPCID.init(jsonValue:))
        else { return nil }
        return CodexResolvedUserInput(requestId: requestId, threadId: threadId)
    }

    public static func response(
        requestId: CodexRPCID,
        answers: [String: [String]]
    ) -> [String: Any] {
        let encodedAnswers = answers.mapValues { ["answers": $0] }
        return [
            "id": requestId.jsonValue,
            "result": ["answers": encodedAnswers],
        ]
    }

    /// Parses the question array shared by App Server requests, hook
    /// `tool_input`, and rollout function-call arguments.
    public static func parseQuestions(
        _ rawQuestions: [[String: Any]]
    ) -> [CodexUserInputRequest.Question]? {
        let questions = rawQuestions.compactMap(parseQuestion)
        guard questions.count == rawQuestions.count, !questions.isEmpty else { return nil }
        return questions
    }

    /// Returns `.some(nil)` when no automatic resolution was requested, and
    /// `nil` when a present value is malformed.
    public static func parseAutoResolutionMs(_ value: Any?) -> Int?? {
        if value is NSNull || value == nil {
            return .some(nil)
        }
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue >= 0,
            number.doubleValue <= Double(Int.max),
            number.doubleValue.rounded(.towardZero) == number.doubleValue
        else { return nil }
        return .some(Int(number.doubleValue))
    }

    private static func parseQuestion(_ object: [String: Any]) -> CodexUserInputRequest.Question? {
        guard let id = object["id"] as? String,
            let question = object["question"] as? String
        else { return nil }

        let rawOptions = object["options"] as? [[String: Any]] ?? []
        let options = rawOptions.compactMap { option -> CodexUserInputRequest.Question.Option? in
            guard let label = option["label"] as? String else { return nil }
            return CodexUserInputRequest.Question.Option(
                label: label,
                description: option["description"] as? String
            )
        }
        guard options.count == rawOptions.count else { return nil }

        guard let isOther = optionalBoolean(object["isOther"], defaultValue: false),
            let isSecret = optionalBoolean(object["isSecret"], defaultValue: false)
        else { return nil }

        return CodexUserInputRequest.Question(
            id: id,
            header: object["header"] as? String,
            question: question,
            options: options,
            isOther: isOther,
            isSecret: isSecret
        )
    }

    private static func optionalBoolean(_ value: Any?, defaultValue: Bool) -> Bool? {
        guard let value else { return defaultValue }
        guard let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return nil }
        return number.boolValue
    }
}
