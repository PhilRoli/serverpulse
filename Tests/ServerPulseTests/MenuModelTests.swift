import XCTest
@testable import ServerPulse

final class MenuModelTests: XCTestCase {
    private let thresholds = Thresholds(diskWarnPct: 85, memWarnPct: 90)
    private let at = Date(timeIntervalSince1970: 1_000)

    private func rows(_ server: ServerConfig, _ state: ServerState?) -> [MenuRow] {
        var states: [UUID: ServerState] = [:]
        states[server.id] = state
        return MenuModel.rows(servers: [server], states: states, thresholds: thresholds)
    }

    func testNoServers() {
        XCTAssertEqual(MenuModel.rows(servers: [], states: [:], thresholds: thresholds), [.addServer])
    }

    func testPlaceholderStates() {
        let server = ServerConfig.fixture(name: "Alpha")
        XCTAssertEqual(rows(server, nil),
                       [.header(name: "Alpha", updatedAt: nil, stale: false), .message("Connecting…")])
        XCTAssertEqual(rows(server, .unconfigured).last, .message("No token"))
        XCTAssertEqual(rows(server, .error(.unauthorized)).last, .message("⚠︎ Token rejected"))
        XCTAssertEqual(rows(server, .error(.outdatedAgent)).last, .message("⚠︎ Agent outdated"))
        XCTAssertEqual(rows(server, .error(.unreachable)).last, .message("⚠︎ Unreachable"))
    }

    func testMetricsRowAndHighlights() {
        let server = ServerConfig.fixture()
        let snap = AgentSnapshot.fixture(containers: [], diskPct: 86, usedMb: 2072, totalMb: 3819)
        let result = rows(server, .ok(snap, at: at))
        XCTAssertEqual(result[0], .header(name: server.name, updatedAt: at, stale: false))
        XCTAssertEqual(result[1], .metrics([
            MetricSegment(text: "CPU 13%", high: false),
            MetricSegment(text: "RAM 2.0/3.7 GB", high: false),
            MetricSegment(text: "Disk 86%", high: true)
        ]))
        XCTAssertEqual(result[2], .message("No containers"))
    }

    func testGroupingAndOrdering() {
        let snap = AgentSnapshot.fixture(containers: [
            .fixture("convex-dashboard-1", project: "convex"),
            .fixture("convex-backend-1", project: "convex", health: .unhealthy),
            .fixture("cda-uebung-api-1", project: "cda-uebung"),
            .fixture("adhoc", project: nil, state: .exited)
        ])
        let result = Array(rows(.fixture(), .ok(snap, at: at)).dropFirst(2))
        XCTAssertEqual(result, [
            .group(name: "convex", dot: .orange, children: [
                ContainerRow(name: "convex-backend-1", dot: .orange, status: "Up 1 day"),
                ContainerRow(name: "convex-dashboard-1", dot: .green, status: "Up 1 day")
            ]),
            .container(ContainerRow(name: "adhoc", dot: .red, status: "Up 1 day")),
            .container(ContainerRow(name: "cda-uebung-api-1", dot: .green, status: "Up 1 day"))
        ])
    }

    func testDockerUnavailableAndStaleHeader() {
        let snap = AgentSnapshot.fixture(containers: nil, dockerError: "socket")
        let result = rows(.fixture(name: "A"), .stale(snap, at: at, error: .unreachable))
        XCTAssertEqual(result.first, .header(name: "A", updatedAt: at, stale: true))
        XCTAssertEqual(result.last, .message("⚠︎ Docker unavailable"))
    }

    func testLanOnlyUnreachableShowsNeutralMessage() {
        let server = ServerConfig.fixture(name: "Pi", lanOnly: true)
        XCTAssertEqual(rows(server, .error(.unreachable)).last, .message("Not on its network"))
        XCTAssertEqual(rows(server, .error(.unauthorized)).last, .message("⚠︎ Token rejected"))
    }

    func testSSHRowAndSeparators() {
        var first = ServerConfig.fixture(name: "A")
        first.sshTarget = "deploy@1.2.3.4"
        let second = ServerConfig.fixture(name: "B")
        let result = MenuModel.rows(servers: [first, second], states: [:], thresholds: thresholds)
        XCTAssertEqual(result, [
            .header(name: "A", updatedAt: nil, stale: false), .message("Connecting…"), .ssh(target: "deploy@1.2.3.4"),
            .separator,
            .header(name: "B", updatedAt: nil, stale: false), .message("Connecting…")
        ])
    }

    func testDots() {
        XCTAssertEqual(MenuModel.dot(for: .fixture("a")), .green)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", health: .healthy)), .green)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", health: .unhealthy)), .orange)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", health: .starting)), .orange)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", state: .paused)), .orange)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", state: .restarting)), .orange)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", state: .exited)), .red)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", state: .dead)), .red)
        XCTAssertEqual(MenuModel.dot(for: .fixture("a", state: .created)), .grey)
        XCTAssertEqual([Dot.green, .red, .grey].max(), .red)
    }
}
