import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("herdr socket protocol")
struct HerdrSocketClientTests {
    @Test("a request is one JSON object on one line")
    func requestIsASingleLine() throws {
        let data = try #require(
            HerdrSocketClient.requestLine(
                method: "pane.focus",
                params: ["pane_id": "w6:p2"],
                id: "test"
            )
        )

        #expect(data.last == 0x0A)
        let json =
            try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any] ?? [:]
        #expect(json["id"] as? String == "test")
        #expect(json["method"] as? String == "pane.focus")
        #expect((json["params"] as? [String: String])?["pane_id"] == "w6:p2")
    }

    /// The pane identifier travels as a JSON value, so a quote in it stays part of the value instead
    /// of ending it — the escaping cmux's AppleScript route has to do by hand.
    @Test("a quote in a parameter cannot break out of its value")
    func quotesStayInsideTheValue() throws {
        let data = try #require(
            HerdrSocketClient.requestLine(
                method: "pane.focus",
                params: ["pane_id": "w1:p1\", \"method\": \"server.stop"]
            )
        )

        let json = try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any] ?? [:]
        #expect(json["method"] as? String == "pane.focus")
    }

    @Test("a result response carries its identifiers")
    func parsesResult() throws {
        let line = Data(
            #"{"id":"agent-notch","result":{"type":"pane_info","pane_id":"w6:p2","focused":true}}"#
                .utf8
        )

        let response = try #require(HerdrSocketClient.parse(responseLine: line))

        #expect(response == .result(["type": "pane_info", "pane_id": "w6:p2"]))
    }

    @Test("an error response is not mistaken for a result")
    func parsesError() throws {
        let line = Data(
            #"{"id":"agent-notch","error":{"code":"not_found","message":"pane not found"}}"#.utf8
        )

        let response = try #require(HerdrSocketClient.parse(responseLine: line))

        #expect(response == .failure(code: "not_found", message: "pane not found"))
    }

    @Test("anything that is neither result nor error resolves to nothing")
    func rejectsUnusableLines() {
        #expect(HerdrSocketClient.parse(responseLine: Data("not json".utf8)) == nil)
        #expect(HerdrSocketClient.parse(responseLine: Data(#"{"id":"x"}"#.utf8)) == nil)
        #expect(HerdrSocketClient.parse(responseLine: Data()) == nil)
    }

    @Test("a socket that answers nothing reports no response")
    func silentSocketReportsNothing() {
        var requestedPath: String?

        let response = HerdrSocketClient.call(
            method: "pane.get",
            params: ["pane_id": "w6:p2"],
            socketPath: "/tmp/missing.sock",
            transport: { path, _ in
                requestedPath = path
                return nil
            }
        )

        #expect(response == nil)
        #expect(requestedPath == "/tmp/missing.sock")
    }
}
