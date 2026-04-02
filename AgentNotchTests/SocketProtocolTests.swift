import Foundation
import Testing
@testable import AgentNotchCore

@Suite("SocketProtocol Tests")
struct SocketProtocolTests {
    @Test("encode produces 4-byte header followed by valid JSON payload")
    func encodeProducesHeaderAndJSON() throws {
        let input: [String: Any] = ["event": "SessionStart", "sessionId": "abc123"]
        let encoded = try SocketProtocol.encode(input)

        // First 4 bytes are length prefix
        #expect(encoded.count >= 4)
        let payloadLength = encoded.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        #expect(Int(payloadLength) == encoded.count - 4)

        // Remaining bytes are valid JSON
        let jsonData = encoded[4...]
        let decoded = try JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any]
        #expect(decoded?["event"] as? String == "SessionStart")
        #expect(decoded?["sessionId"] as? String == "abc123")
    }

    @Test("decode extracts message and reports correct bytesConsumed")
    func decodeExtractsMessage() throws {
        let input: [String: Any] = ["type": "test", "value": 42]
        let encoded = try SocketProtocol.encode(input)

        let result = try SocketProtocol.decode(encoded)
        #expect(result != nil)
        #expect(result?.message["type"] as? String == "test")
        #expect(result?.message["value"] as? Int == 42)
        #expect(result?.bytesConsumed == encoded.count)
    }

    @Test("decode returns nil for incomplete data less than 4 bytes")
    func decodeReturnsNilForIncompleteData() throws {
        let tooShort = Data([0x01, 0x02])
        let result = try SocketProtocol.decode(tooShort)
        #expect(result == nil)
    }

    @Test("decode returns nil when payload is incomplete")
    func decodeReturnsNilForIncompletePayload() throws {
        let input: [String: Any] = ["hello": "world"]
        let encoded = try SocketProtocol.encode(input)
        // Truncate the data so payload is incomplete
        let truncated = encoded.prefix(encoded.count - 2)
        let result = try SocketProtocol.decode(truncated)
        #expect(result == nil)
    }
}
