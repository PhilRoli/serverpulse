import XCTest
@testable import ServerPulse

final class ModelsTests: XCTestCase {
    func testDecodesV2Payload() throws {
        let json = """
        {"version":2,"hostname":"rettstat-1","uptime_s":345600,
         "cpu":{"cores":2,"pct":12.5,"load_1m":0.14},
         "memory":{"used_mb":2072,"total_mb":3819},
         "disk":{"path":"/","used_pct":71},
         "containers":[{"name":"convex-backend-1","project":"convex","state":"running",
                        "health":"healthy","status":"Up 4 days (healthy)"},
                       {"name":"x","project":null,"state":"weird","health":"none","status":""}],
         "docker_error":null}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snap = try decoder.decode(AgentSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.cpu.load1m, 0.14)
        XCTAssertEqual(snap.memory.usedMb, 2072)
        XCTAssertEqual(snap.memory.usedPct, 54)
        XCTAssertEqual(snap.disk.usedPct, 71)
        XCTAssertEqual(snap.uptimeS, 345600)
        XCTAssertEqual(snap.containers?[0].health, .healthy)
        XCTAssertEqual(snap.containers?[1].state, .unknown)
        XCTAssertNil(snap.containers?[1].health)
    }

    func testMemoryUsedPctNilWithoutTotal() {
        XCTAssertNil(AgentSnapshot.Memory(usedMb: 1, totalMb: 0).usedPct)
        XCTAssertNil(AgentSnapshot.Memory(usedMb: nil, totalMb: 10).usedPct)
    }

    func testServerStateHelpers() {
        let snap = AgentSnapshot.fixture()
        let at = Date()
        XCTAssertEqual(ServerState.ok(snap, at: at).snapshot, snap)
        XCTAssertTrue(ServerState.stale(snap, at: at, error: .unreachable).isStale)
        XCTAssertNil(ServerState.loading.snapshot)
        XCTAssertFalse(ServerState.error(.unreachable).isStale)
    }

    func testErrorLabels() {
        XCTAssertEqual(MonitorError.unauthorized.label, "Token rejected")
        XCTAssertEqual(MonitorError.outdatedAgent.label, "Agent outdated")
        XCTAssertEqual(MonitorError.unreachable.label, "Unreachable")
        XCTAssertEqual(MonitorError.http(502).label, "HTTP 502")
        XCTAssertEqual(MonitorError.decoding.label, "Bad response")
    }
}
