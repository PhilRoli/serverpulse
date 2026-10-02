import XCTest
@testable import ServerPulse

private final class RequestBox: @unchecked Sendable {
    var request: URLRequest?
}

private struct FakeTransport: HTTPTransport {
    var box = RequestBox()
    var respond: @Sendable (URLRequest) throws -> (Data, Int)

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        box.request = request
        return try respond(request)
    }
}

final class AgentClientTests: XCTestCase {
    private let url = URL(string: "https://metrics.example/metrics")!

    private func makeClient(_ body: String, status: Int = 200) -> (AgentClient, RequestBox) {
        let transport = FakeTransport { _ in (Data(body.utf8), status) }
        return (AgentClient(transport: transport), transport.box)
    }

    private func assertThrows(_ expected: MonitorError, _ client: AgentClient,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client.fetch(url: url, token: "t")
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? MonitorError, expected, file: file, line: line)
        }
    }

    func testSendsBearerTokenAndTimeout() async throws {
        let (client, box) = makeClient(JSONFixtures.v2)
        _ = try await client.fetch(url: url, token: "s3cret")
        XCTAssertEqual(box.request?.url, url)
        XCTAssertEqual(box.request?.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertEqual(box.request?.timeoutInterval, 10)
    }

    func testDecodesV2() async throws {
        let snap = try await makeClient(JSONFixtures.v2).0.fetch(url: url, token: "t")
        XCTAssertEqual(snap.hostname, "rettstat-1")
        XCTAssertEqual(snap.containers?.first?.project, "convex")
    }

    func testOldAgentIsOutdated() async {
        await assertThrows(.outdatedAgent, makeClient(JSONFixtures.v1).0)
        await assertThrows(.outdatedAgent, makeClient(#"{"version":1}"#).0)
    }

    func testGarbageIsDecodingError() async {
        await assertThrows(.decoding, makeClient("<html>").0)
        await assertThrows(.decoding, makeClient(#"{"version":2}"#).0) // missing required objects
    }

    func testStatusMapping() async {
        await assertThrows(.unauthorized, makeClient("", status: 401).0)
        await assertThrows(.http(502), makeClient("", status: 502).0)
        await assertThrows(.http(404), makeClient("", status: 404).0)
    }

    func testTransportFailureIsUnreachable() async {
        let client = AgentClient(transport: FakeTransport { _ in throw URLError(.timedOut) })
        await assertThrows(.unreachable, client)
    }

    func testCancellationPropagates() async {
        let client = AgentClient(transport: FakeTransport { _ in throw URLError(.cancelled) })
        do {
            _ = try await client.fetch(url: url, token: "t")
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
