import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Codex App Server WebSocket codec")
struct CodexWebSocketCodecTests {
    @Test("Upgrade parser validates the accept key and preserves the first frame")
    func handshake() throws {
        let generated = CodexWebSocketHandshake.makeRequest()
        let frame = serverFrame(opcode: 0x1, payload: Data("{}".utf8))
        var response = Data(
            [
                "HTTP/1.1 101 Switching Protocols",
                "Upgrade: websocket",
                "Connection: Upgrade",
                "Sec-WebSocket-Accept: \(generated.expectedAccept)",
                "",
                "",
            ].joined(separator: "\r\n").utf8
        )
        response.append(frame)

        #expect(
            try CodexWebSocketHandshake.consumeResponse(
                from: &response,
                expectedAccept: generated.expectedAccept
            )
        )
        #expect(response == frame)
    }

    @Test("Decoder handles split and fragmented server text plus ping")
    func fragmentedFrames() throws {
        let first = serverFrame(
            opcode: 0x1,
            payload: Data(#"{"method":"item/"#.utf8),
            isFinal: false
        )
        let second = serverFrame(
            opcode: 0x0,
            payload: Data(#"tool/requestUserInput"}"#.utf8)
        )
        let ping = serverFrame(opcode: 0x9, payload: Data("ok".utf8))
        let bytes = first + second + ping
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(try decoder.append(Data(bytes.prefix(3))).isEmpty)
        let messages = try decoder.append(Data(bytes.dropFirst(3)))
        #expect(
            messages == [
                .text(#"{"method":"item/tool/requestUserInput"}"#),
                .ping(Data("ok".utf8)),
            ])
    }

    @Test("Client text frames are masked and round-trip to the original JSON")
    func maskedClientFrame() throws {
        let text = #"{"method":"initialized","params":{}}"#
        let frame = try CodexWebSocketCodec.encodeText(text)
        #expect(frame[0] & 0x0F == 0x1)
        #expect(frame[1] & 0x80 != 0)

        let payloadLength = Int(frame[1] & 0x7F)
        #expect(payloadLength == text.utf8.count)
        let mask = Array(frame[2..<6])
        let decoded = Data(
            frame[6...].enumerated().map { index, byte in
                byte ^ mask[index % 4]
            })
        #expect(String(data: decoded, encoding: .utf8) == text)
    }

    // MARK: - Handshake rejection
    //
    // The handshake is the only place that proves the pipe on the other end really is the App
    // Server. Every one of these has to fail closed, or a wrong process gets fed JSON-RPC.

    @Test("An incomplete header is not consumed and reports no handshake yet")
    func handshakeWaitsForFullHeader() throws {
        var buffer = Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n".utf8)
        let original = buffer

        #expect(try !CodexWebSocketHandshake.consumeResponse(from: &buffer, expectedAccept: "x"))
        // Nothing may be consumed, or the bytes would be lost before the rest arrives.
        #expect(buffer == original)
    }

    @Test(
        "Handshakes that are not a valid 101 upgrade are rejected",
        arguments: [
            ("non-101 status", "HTTP/1.1 400 Bad Request", "websocket", true),
            ("missing upgrade header", "HTTP/1.1 101 Switching Protocols", nil, true),
            ("wrong upgrade value", "HTTP/1.1 101 Switching Protocols", "h2c", true),
            ("mismatched accept key", "HTTP/1.1 101 Switching Protocols", "websocket", false),
        ] as [(String, String, String?, Bool)]
    )
    func handshakeRejections(
        name: String,
        status: String,
        upgrade: String?,
        correctAccept: Bool
    ) throws {
        var lines = [status]
        if let upgrade { lines.append("Upgrade: \(upgrade)") }
        lines.append("Sec-WebSocket-Accept: \(correctAccept ? "expected" : "wrong")")
        lines.append("")
        lines.append("")
        var buffer = Data(lines.joined(separator: "\r\n").utf8)

        #expect(throws: CodexWebSocketError.invalidHandshake) {
            try CodexWebSocketHandshake.consumeResponse(from: &buffer, expectedAccept: "expected")
        }
    }

    @Test("A header that is not UTF-8 is rejected rather than lossily decoded")
    func handshakeRejectsInvalidUTF8() {
        var buffer = Data([0xFF, 0xFE, 0x00]) + Data("\r\n\r\n".utf8)

        #expect(throws: CodexWebSocketError.invalidHandshake) {
            try CodexWebSocketHandshake.consumeResponse(from: &buffer, expectedAccept: "expected")
        }
    }

    @Test("The generated request carries the headers the upgrade requires")
    func handshakeRequestShape() throws {
        let generated = CodexWebSocketHandshake.makeRequest()
        let request = try #require(String(data: generated.request, encoding: .utf8))

        #expect(request.hasPrefix("GET / HTTP/1.1\r\n"))
        #expect(request.contains("Upgrade: websocket\r\n"))
        #expect(request.contains("Connection: Upgrade\r\n"))
        #expect(request.contains("Sec-WebSocket-Version: 13\r\n"))
        #expect(request.hasSuffix("\r\n\r\n"))

        // A 16-byte nonce is required by the protocol; base64 makes that 24 characters.
        let key = try #require(
            request
                .components(separatedBy: "\r\n")
                .first { $0.hasPrefix("Sec-WebSocket-Key: ") }?
                .replacingOccurrences(of: "Sec-WebSocket-Key: ", with: "")
        )
        #expect(Data(base64Encoded: key)?.count == 16)
        #expect(!generated.expectedAccept.isEmpty)
        #expect(generated.expectedAccept != key)
    }

    @Test("Each request uses a fresh nonce, so the accept key is not reusable")
    func handshakeNonceIsPerRequest() {
        let a = CodexWebSocketHandshake.makeRequest()
        let b = CodexWebSocketHandshake.makeRequest()

        #expect(a.request != b.request)
        #expect(a.expectedAccept != b.expectedAccept)
    }

    // MARK: - Client frame encoding

    @Test("Pong echoes the ping payload and close carries none, both masked")
    func encodesControlFrames() throws {
        let pong = try CodexWebSocketCodec.encodePong(Data("ok".utf8))
        #expect(pong[0] == 0x80 | 0xA)
        #expect(pong[1] & 0x80 != 0)
        #expect(unmaskClientPayload(pong) == Data("ok".utf8))

        let close = try CodexWebSocketCodec.encodeClose()
        #expect(close[0] == 0x80 | 0x8)
        #expect(close[1] & 0x7F == 0)
        #expect(unmaskClientPayload(close).isEmpty)
    }

    /// The three length encodings are a classic source of off-by-one framing bugs, so each
    /// boundary is pinned: 125 still fits inline, 126 switches to a 16-bit length, and
    /// 65536 switches to a 64-bit one.
    @Test(
        "Payload length selects the right wire encoding",
        arguments: [
            (125, UInt8(125), 2),
            (126, UInt8(126), 4),
            (65_535, UInt8(126), 4),
            (65_536, UInt8(127), 10),
        ]
    )
    func encodesEachLengthForm(count: Int, marker: UInt8, maskOffset: Int) throws {
        let text = String(repeating: "a", count: count)
        let frame = try CodexWebSocketCodec.encodeText(text)

        #expect(frame[1] & 0x7F == marker)
        switch marker {
        case 126:
            #expect(Int(frame[2]) << 8 | Int(frame[3]) == count)
        case 127:
            let length = (2..<10).reduce(UInt64(0)) { $0 << 8 | UInt64(frame[$1]) }
            #expect(length == UInt64(count))
        default:
            break
        }
        // The mask sits immediately after the length, and the payload after that.
        let mask = Array(frame[maskOffset..<(maskOffset + 4)])
        let payload = Data(
            frame[(maskOffset + 4)...].enumerated().map { $0.element ^ mask[$0.offset % 4] }
        )
        #expect(payload == Data(text.utf8))
    }

    @Test("Encoding refuses a payload over the size limit")
    func encodeRejectsOversizedPayload() {
        let oversized = Data(count: CodexWebSocketCodec.maximumPayloadBytes + 1)

        #expect(throws: CodexWebSocketError.payloadTooLarge) {
            try CodexWebSocketCodec.encodePong(oversized)
        }
    }

    // MARK: - Server frame decoding

    @Test("Extended lengths round-trip through the decoder")
    func decodesExtendedLengths() throws {
        for count in [126, 65_535, 65_536] {
            let text = String(repeating: "b", count: count)
            let decoder = CodexWebSocketCodec.Decoder()

            let messages = try decoder.append(serverFrame(opcode: 0x1, payload: Data(text.utf8)))

            #expect(messages == [.text(text)])
        }
    }

    /// Servers are not required to mask, but nothing forbids it either, so the decoder has to
    /// unmask when the bit is set instead of handing back scrambled bytes.
    @Test("A masked server frame is unmasked")
    func decodesMaskedServerFrame() throws {
        let decoder = CodexWebSocketCodec.Decoder()
        let frame = serverFrame(opcode: 0x1, payload: Data("hello".utf8), mask: [1, 2, 3, 4])

        #expect(try decoder.append(frame) == [.text("hello")])
    }

    @Test("Close and pong are handled: close surfaces, pong is silently absorbed")
    func decodesCloseAndPong() throws {
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(try decoder.append(serverFrame(opcode: 0xA, payload: Data("x".utf8))).isEmpty)
        #expect(try decoder.append(serverFrame(opcode: 0x8, payload: Data())) == [.close])
    }

    @Test("A frame arriving one byte at a time still decodes")
    func decodesByteAtATime() throws {
        let decoder = CodexWebSocketCodec.Decoder()
        let frame = serverFrame(opcode: 0x1, payload: Data(#"{"a":1}"#.utf8))
        var messages: [CodexWebSocketMessage] = []

        for byte in frame {
            messages += try decoder.append(Data([byte]))
        }

        #expect(messages == [.text(#"{"a":1}"#)])
    }

    // MARK: - Decoder rejection
    //
    // Everything here is a malformed or unexpected frame. The decoder is the boundary against a
    // process that is not the App Server, or a protocol change, so all of it must fail closed
    // rather than guess.

    @Test("Reserved bits are rejected")
    func rejectsReservedBits() {
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(throws: CodexWebSocketError.invalidFrame) {
            try decoder.append(Data([0x80 | 0x10 | 0x1, 0x00]))
        }
    }

    @Test("Binary frames are rejected, keeping a protocol change fail-closed")
    func rejectsBinaryFrames() {
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(throws: CodexWebSocketError.invalidFrame) {
            try decoder.append(serverFrame(opcode: 0x2, payload: Data([0x00])))
        }
    }

    @Test("An unassigned opcode is rejected")
    func rejectsUnknownOpcode() {
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(throws: CodexWebSocketError.invalidFrame) {
            try decoder.append(serverFrame(opcode: 0x3, payload: Data()))
        }
    }

    @Test("A fragmented control frame is rejected")
    func rejectsFragmentedControlFrame() {
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(throws: CodexWebSocketError.invalidFrame) {
            try decoder.append(serverFrame(opcode: 0x9, payload: Data(), isFinal: false))
        }
    }

    @Test("A control frame over 125 bytes is rejected")
    func rejectsOversizedControlFrame() {
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(throws: CodexWebSocketError.invalidFrame) {
            try decoder.append(serverFrame(opcode: 0x9, payload: Data(count: 126)))
        }
    }

    @Test("A continuation with nothing to continue is rejected")
    func rejectsOrphanContinuation() {
        let decoder = CodexWebSocketCodec.Decoder()

        #expect(throws: CodexWebSocketError.invalidFrame) {
            try decoder.append(serverFrame(opcode: 0x0, payload: Data("x".utf8)))
        }
    }

    @Test("A new text frame in the middle of a fragmented one is rejected")
    func rejectsInterleavedTextFrame() throws {
        let decoder = CodexWebSocketCodec.Decoder()
        _ = try decoder.append(serverFrame(opcode: 0x1, payload: Data("a".utf8), isFinal: false))

        #expect(throws: CodexWebSocketError.invalidFrame) {
            try decoder.append(serverFrame(opcode: 0x1, payload: Data("b".utf8)))
        }
    }

    @Test("Text that is not UTF-8 is rejected, whole or fragmented")
    func rejectsInvalidUTF8Text() throws {
        let whole = CodexWebSocketCodec.Decoder()
        #expect(throws: CodexWebSocketError.invalidUTF8) {
            try whole.append(serverFrame(opcode: 0x1, payload: Data([0xFF, 0xFE])))
        }

        let fragmented = CodexWebSocketCodec.Decoder()
        _ = try fragmented.append(
            serverFrame(opcode: 0x1, payload: Data([0xFF]), isFinal: false)
        )
        #expect(throws: CodexWebSocketError.invalidUTF8) {
            try fragmented.append(serverFrame(opcode: 0x0, payload: Data([0xFE])))
        }
    }

    /// The length is checked before the bytes are waited for, so an absurd declared length is
    /// rejected immediately instead of buffering towards it.
    @Test("A declared length over the limit is rejected from the header alone")
    func rejectsOversizedDeclaredLength() {
        var header = Data([0x80 | 0x1, 127])
        var length = UInt64(CodexWebSocketCodec.maximumPayloadBytes + 1).bigEndian
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }

        #expect(throws: CodexWebSocketError.payloadTooLarge) {
            try CodexWebSocketCodec.Decoder().append(header)
        }
    }

    @Test("A 64-bit length that overflows Int is rejected")
    func rejectsLengthBeyondInt() {
        let header = Data([0x80 | 0x1, 127] + Array(repeating: UInt8(0xFF), count: 8))

        #expect(throws: CodexWebSocketError.payloadTooLarge) {
            try CodexWebSocketCodec.Decoder().append(header)
        }
    }

    @Test("Fragments are rejected once they add up past the limit")
    func rejectsOversizedFragmentTotal() throws {
        let half = CodexWebSocketCodec.maximumPayloadBytes / 2 + 1
        let decoder = CodexWebSocketCodec.Decoder()
        _ = try decoder.append(serverFrame(opcode: 0x1, payload: Data(count: half), isFinal: false))

        #expect(throws: CodexWebSocketError.payloadTooLarge) {
            try decoder.append(serverFrame(opcode: 0x0, payload: Data(count: half)))
        }
    }

    @Test("Every error explains itself, in words that name the App Server")
    func errorsHaveDistinctDescriptions() {
        let errors: [CodexWebSocketError] = [
            .invalidHandshake, .invalidFrame, .payloadTooLarge, .invalidUTF8, .closed,
        ]
        let descriptions = errors.map { $0.errorDescription ?? "" }

        #expect(descriptions.allSatisfy { $0.contains("Codex App Server") })
        #expect(Set(descriptions).count == errors.count)
    }

    // MARK: - Helpers

    /// Builds a server-to-client frame, picking the length encoding the payload requires.
    private func serverFrame(
        opcode: UInt8,
        payload: Data,
        isFinal: Bool = true,
        mask: [UInt8]? = nil
    ) -> Data {
        var data = Data([(isFinal ? 0x80 : 0) | opcode])
        let maskBit: UInt8 = mask == nil ? 0 : 0x80
        switch payload.count {
        case ...125:
            data.append(maskBit | UInt8(payload.count))
        case ...Int(UInt16.max):
            data.append(maskBit | 126)
            var length = UInt16(payload.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        default:
            data.append(maskBit | 127)
            var length = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        }
        if let mask {
            data.append(contentsOf: mask)
            data.append(
                contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % mask.count] }
            )
        } else {
            data.append(payload)
        }
        return data
    }

    /// Strips the 4-byte mask a client frame must carry, for frames short enough to have an
    /// inline length.
    private func unmaskClientPayload(_ frame: Data) -> Data {
        let mask = Array(frame[2..<6])
        return Data(frame[6...].enumerated().map { $0.element ^ mask[$0.offset % 4] })
    }
}
