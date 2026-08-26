import CryptoKit
import Foundation

enum CodexWebSocketError: LocalizedError {
    case invalidHandshake
    case invalidFrame
    case payloadTooLarge
    case invalidUTF8
    case closed

    var errorDescription: String? {
        switch self {
        case .invalidHandshake: "Codex App Server returned an invalid WebSocket handshake"
        case .invalidFrame: "Codex App Server returned an invalid WebSocket frame"
        case .payloadTooLarge: "Codex App Server WebSocket payload exceeded the size limit"
        case .invalidUTF8: "Codex App Server returned invalid UTF-8"
        case .closed: "Codex App Server closed the WebSocket"
        }
    }
}

enum CodexWebSocketMessage: Equatable {
    case text(String)
    case ping(Data)
    case close
}

enum CodexWebSocketHandshake {
    private static let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    static func makeRequest() -> (request: Data, expectedAccept: String) {
        var random = SystemRandomNumberGenerator()
        let nonce = Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &random) })
        let key = nonce.base64EncodedString()
        let digest = Insecure.SHA1.hash(data: Data((key + magicGUID).utf8))
        let accept = Data(digest).base64EncodedString()
        let request = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            "",
        ].joined(separator: "\r\n")
        return (Data(request.utf8), accept)
    }

    /// Consumes an HTTP Upgrade response, preserving any WebSocket bytes that
    /// arrived in the same pipe read.
    static func consumeResponse(
        from buffer: inout Data,
        expectedAccept: String
    ) throws -> Bool {
        let delimiter = Data([13, 10, 13, 10])
        guard let range = buffer.range(of: delimiter) else { return false }

        let headerData = Data(buffer[..<range.upperBound])
        buffer.removeSubrange(..<range.upperBound)
        guard let header = String(data: headerData, encoding: .utf8) else {
            throw CodexWebSocketError.invalidHandshake
        }
        let lines = header.components(separatedBy: "\r\n")
        guard lines.first?.contains(" 101 ") == true else {
            throw CodexWebSocketError.invalidHandshake
        }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            fields[name] = value
        }
        guard fields["upgrade"]?.lowercased() == "websocket",
            fields["sec-websocket-accept"] == expectedAccept
        else {
            throw CodexWebSocketError.invalidHandshake
        }
        return true
    }
}

enum CodexWebSocketCodec {
    static let maximumPayloadBytes = 16 * 1_024 * 1_024

    static func encodeText(_ text: String) throws -> Data {
        try encodeClientFrame(opcode: 0x1, payload: Data(text.utf8))
    }

    static func encodePong(_ payload: Data) throws -> Data {
        try encodeClientFrame(opcode: 0xA, payload: payload)
    }

    static func encodeClose() throws -> Data {
        try encodeClientFrame(opcode: 0x8, payload: Data())
    }

    /// WebSocket clients must mask every frame sent to the server.
    private static func encodeClientFrame(opcode: UInt8, payload: Data) throws -> Data {
        guard payload.count <= maximumPayloadBytes else {
            throw CodexWebSocketError.payloadTooLarge
        }

        var output = Data([0x80 | opcode])
        let length = payload.count
        if length <= 125 {
            output.append(0x80 | UInt8(length))
        } else if length <= Int(UInt16.max) {
            output.append(0x80 | 126)
            appendBigEndian(UInt16(length), to: &output)
        } else {
            output.append(0x80 | 127)
            appendBigEndian(UInt64(length), to: &output)
        }

        var random = SystemRandomNumberGenerator()
        let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max, using: &random) }
        output.append(contentsOf: mask)
        output.append(
            contentsOf: payload.enumerated().map { index, byte in
                byte ^ mask[index % mask.count]
            })
        return output
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    final class Decoder {
        private var buffer = Data()
        private var fragmentedOpcode: UInt8?
        private var fragmentedPayload = Data()

        func append(_ data: Data) throws -> [CodexWebSocketMessage] {
            buffer.append(data)
            var messages: [CodexWebSocketMessage] = []

            while let frame = try decodeFrame() {
                let isControl = frame.opcode >= 0x8
                if isControl, !frame.isFinal || frame.payload.count > 125 {
                    throw CodexWebSocketError.invalidFrame
                }

                switch frame.opcode {
                case 0x0:
                    guard fragmentedOpcode != nil else {
                        throw CodexWebSocketError.invalidFrame
                    }
                    try appendFragment(frame.payload)
                    if frame.isFinal {
                        guard fragmentedOpcode == 0x1,
                            let text = String(data: fragmentedPayload, encoding: .utf8)
                        else {
                            throw CodexWebSocketError.invalidUTF8
                        }
                        messages.append(.text(text))
                        fragmentedOpcode = nil
                        fragmentedPayload.removeAll(keepingCapacity: true)
                    }
                case 0x1:
                    guard fragmentedOpcode == nil else {
                        throw CodexWebSocketError.invalidFrame
                    }
                    if frame.isFinal {
                        guard let text = String(data: frame.payload, encoding: .utf8) else {
                            throw CodexWebSocketError.invalidUTF8
                        }
                        messages.append(.text(text))
                    } else {
                        fragmentedOpcode = frame.opcode
                        fragmentedPayload = frame.payload
                    }
                case 0x2:
                    // Agent Notch's App Server messages are JSON text. Rejecting
                    // binary data keeps a protocol change fail-closed.
                    throw CodexWebSocketError.invalidFrame
                case 0x8:
                    messages.append(.close)
                case 0x9:
                    messages.append(.ping(frame.payload))
                case 0xA:
                    break
                default:
                    throw CodexWebSocketError.invalidFrame
                }
            }
            return messages
        }

        private func appendFragment(_ payload: Data) throws {
            guard fragmentedPayload.count + payload.count <= CodexWebSocketCodec.maximumPayloadBytes
            else {
                throw CodexWebSocketError.payloadTooLarge
            }
            fragmentedPayload.append(payload)
        }

        private func decodeFrame() throws -> (isFinal: Bool, opcode: UInt8, payload: Data)? {
            // `removeSubrange` may leave a slice-like backing store. Normalize
            // indices before using integer offsets for the wire format.
            if buffer.startIndex != 0 {
                buffer = Data(buffer)
            }
            guard buffer.count >= 2 else { return nil }
            let first = buffer[buffer.startIndex]
            let second = buffer[buffer.index(after: buffer.startIndex)]
            let isFinal = first & 0x80 != 0
            let hasReservedBits = first & 0x70 != 0
            guard !hasReservedBits else { throw CodexWebSocketError.invalidFrame }

            let isMasked = second & 0x80 != 0
            var offset = 2
            let shortLength = Int(second & 0x7F)
            let payloadLength: Int
            switch shortLength {
            case 126:
                guard buffer.count >= offset + 2 else { return nil }
                payloadLength = Int(readBigEndianUInt16(buffer, at: offset))
                offset += 2
            case 127:
                guard buffer.count >= offset + 8 else { return nil }
                let length = readBigEndianUInt64(buffer, at: offset)
                guard length <= UInt64(Int.max) else {
                    throw CodexWebSocketError.payloadTooLarge
                }
                payloadLength = Int(length)
                offset += 8
            default:
                payloadLength = shortLength
            }
            guard payloadLength <= CodexWebSocketCodec.maximumPayloadBytes else {
                throw CodexWebSocketError.payloadTooLarge
            }

            let mask: [UInt8]?
            if isMasked {
                guard buffer.count >= offset + 4 else { return nil }
                mask = Array(buffer[offset..<(offset + 4)])
                offset += 4
            } else {
                mask = nil
            }
            guard buffer.count >= offset + payloadLength else { return nil }

            var payload = Data(buffer[offset..<(offset + payloadLength)])
            if let mask {
                payload = Data(
                    payload.enumerated().map { index, byte in
                        byte ^ mask[index % mask.count]
                    })
            }
            buffer.removeSubrange(..<(offset + payloadLength))
            return (isFinal, first & 0x0F, payload)
        }

        private func readBigEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
            (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        }

        private func readBigEndianUInt64(_ data: Data, at offset: Int) -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<8 {
                value = (value << 8) | UInt64(data[offset + index])
            }
            return value
        }
    }
}
