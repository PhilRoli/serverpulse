import XCTest
@testable import ServerPulse

final class HealthEvaluatorTests: XCTestCase {
    private let server = ServerConfig.fixture(name: "Ambulance")
    private let thresholds = Thresholds(diskWarnPct: 85, memWarnPct: 90)
    private let at = Date()

    private func kinds(_ state: ServerState, active: Set<String> = []) -> [Issue.Kind] {
        HealthEvaluator.issues(server: server, state: state, thresholds: thresholds, active: active).map(\.kind)
    }

    func testNoIssuesWhileLoadingOrUnconfigured() {
        XCTAssertEqual(kinds(.loading), [])
        XCTAssertEqual(kinds(.unconfigured), [])
    }

    func testConnectionErrors() {
        XCTAssertEqual(kinds(.error(.unauthorized)), [.authFailed])
        XCTAssertEqual(kinds(.error(.outdatedAgent)), [.agentOutdated])
        XCTAssertEqual(kinds(.error(.unreachable)), [.agentUnreachable])
        XCTAssertEqual(kinds(.error(.http(502))), [.agentUnreachable])
        XCTAssertEqual(kinds(.error(.decoding)), [.agentUnreachable])
    }

    func testContainerIssues() {
        let snap = AgentSnapshot.fixture(containers: [
            .fixture("b-exited", state: .exited),
            .fixture("a-dead", state: .dead),
            .fixture("c-sick", health: .unhealthy),
            .fixture("d-ok", health: .healthy),
            .fixture("e-paused", state: .paused),
            .fixture("f-restarting", state: .restarting),
            .fixture("g-starting", health: .starting)
        ])
        let issues = HealthEvaluator.issues(server: server, state: .ok(snap, at: at), thresholds: thresholds)
        XCTAssertEqual(issues.map(\.kind), [.containerDown, .containerDown, .containerUnhealthy])
        XCTAssertEqual(issues.map(\.subject), ["a-dead", "b-exited", "c-sick"])
        XCTAssertEqual(issues.first?.serverID, server.id)
        XCTAssertEqual(issues.first?.serverName, "Ambulance")
    }

    func testDockerUnavailable() {
        let snap = AgentSnapshot.fixture(containers: nil, dockerError: "socket")
        XCTAssertEqual(kinds(.ok(snap, at: at)), [.dockerUnavailable])
    }

    func testDiskThresholdBoundary() {
        let issues = HealthEvaluator.issues(server: server, state: .ok(.fixture(diskPct: 85), at: at),
                                            thresholds: thresholds)
        XCTAssertEqual(issues.map(\.kind), [.diskHigh])
        XCTAssertEqual(issues.first?.value, 85)
        XCTAssertEqual(kinds(.ok(.fixture(diskPct: 84), at: at)), [])
    }

    func testMemThresholdBoundary() {
        XCTAssertEqual(kinds(.ok(.fixture(usedMb: 900, totalMb: 1000), at: at)), [.memHigh])
        XCTAssertEqual(kinds(.ok(.fixture(usedMb: 890, totalMb: 1000), at: at)), [])
    }

    func testMemHysteresisKeepsActiveIssue() {
        let active: Set<String> = [Issue.key(.memHigh)]
        XCTAssertEqual(kinds(.ok(.fixture(usedMb: 870, totalMb: 1000), at: at), active: active), [.memHigh])
        XCTAssertEqual(kinds(.ok(.fixture(usedMb: 850, totalMb: 1000), at: at), active: active), [.memHigh])
        XCTAssertEqual(kinds(.ok(.fixture(usedMb: 840, totalMb: 1000), at: at), active: active), [])
        XCTAssertEqual(kinds(.ok(.fixture(usedMb: 870, totalMb: 1000), at: at)), [])
    }

    func testStaleKeepsSnapshotIssuesPlusUnreachable() {
        let snap = AgentSnapshot.fixture(containers: [.fixture("x", state: .exited)])
        XCTAssertEqual(kinds(.stale(snap, at: at, error: .unreachable)), [.agentUnreachable, .containerDown])
    }

    func testKeysAndLevels() {
        let issue = Issue(serverID: server.id, serverName: "A", kind: .containerDown, subject: "web", value: nil)
        XCTAssertEqual(issue.key, "containerDown:web")
        XCTAssertEqual(Issue.key(.diskHigh), "diskHigh:")
        XCTAssertFalse(issue.isAgentLevel)
        XCTAssertTrue(issue.isSnapshotDerived)
        let agent = Issue(serverID: server.id, serverName: "A", kind: .agentUnreachable, subject: nil, value: nil)
        XCTAssertTrue(agent.isAgentLevel)
        XCTAssertFalse(agent.isSnapshotDerived)
    }
}
