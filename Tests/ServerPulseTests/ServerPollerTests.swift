import XCTest
@testable import ServerPulse

@MainActor
final class ServerPollerTests: XCTestCase {
    private var client: FakeClient!
    private var tokens: FakeTokens!
    private var server: ServerConfig!
    private var config: AppConfig!
    private var clock = Date(timeIntervalSince1970: 1_000)
    private var updates: [ServerState] = []

    override func setUp() async throws {
        client = FakeClient()
        tokens = FakeTokens()
        server = .fixture()
        tokens.tokens[server.id] = "tok"
        config = AppConfig()
        config.servers = [server]
        updates = []
    }

    private func makePoller() -> ServerPoller {
        let poller = ServerPoller(
            client: client, tokens: tokens, now: { [unowned self] in self.clock }, startsLoops: false)
        poller.onUpdate = { [unowned self] _, state in self.updates.append(state) }
        poller.apply(config)
        return poller
    }

    func testApplyPublishesLoading() {
        let poller = makePoller()
        XCTAssertEqual(poller.states[server.id], .loading)
        XCTAssertEqual(updates, [.loading])
    }

    func testSuccessPublishesOK() async {
        let poller = makePoller()
        let snap = AgentSnapshot.fixture()
        client.results = [.success(snap)]
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .ok(snap, at: clock))
        XCTAssertEqual(client.calls.first?.token, "tok")
        XCTAssertEqual(client.calls.first?.url, server.url)
    }

    func testFailuresWithoutSnapshot() async {
        let poller = makePoller()
        client.results = [.failure(.unreachable), .failure(.unreachable)]
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .loading)
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .error(.unreachable))
    }

    func testOfflineKeepsSnapshotState() async {
        let poller = makePoller()
        let snap = AgentSnapshot.fixture()
        client.results = [.success(snap), .failure(.offline), .failure(.offline)]
        await poller.refresh(server.id)
        await poller.refresh(server.id)
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .ok(snap, at: clock))
    }

    func testOfflineWithoutSnapshotStaysLoading() async {
        let poller = makePoller()
        client.results = [.failure(.offline), .failure(.offline)]
        await poller.refresh(server.id)
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .loading)
    }

    func testStaleAfterTwoFailuresKeepsLastSnapshot() async {
        let poller = makePoller()
        let snap = AgentSnapshot.fixture()
        let firstSuccess = clock
        client.results = [.success(snap), .failure(.http(502)), .failure(.http(502))]
        await poller.refresh(server.id)
        clock = clock.addingTimeInterval(30)
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .ok(snap, at: firstSuccess))
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .stale(snap, at: firstSuccess, error: .http(502)))
    }

    func testSuccessResetsFailureCount() async {
        let poller = makePoller()
        let snap = AgentSnapshot.fixture()
        client.results = [.success(snap), .failure(.unreachable), .success(snap), .failure(.unreachable)]
        for _ in 0..<4 { await poller.refresh(server.id) }
        XCTAssertEqual(poller.states[server.id], .ok(snap, at: clock))
    }

    func testUnauthorizedParksUntilTokenChanges() async {
        let poller = makePoller()
        client.results = [.failure(.unauthorized)]
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .error(.unauthorized))
        XCTAssertTrue(poller.isParked(server.id))
        poller.apply(config, tokenChanged: [server.id])
        XCTAssertFalse(poller.isParked(server.id))
    }

    func testMissingTokenIsUnconfigured() async {
        tokens.tokens = [:]
        let poller = makePoller()
        await poller.refresh(server.id)
        XCTAssertEqual(poller.states[server.id], .unconfigured)
        XCTAssertTrue(poller.isParked(server.id))
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testApplyRestartsOnlyChangedServers() {
        let second = ServerConfig.fixture(name: "Beta", url: "https://b.example/metrics")
        config.servers.append(second)
        let poller = makePoller()
        let firstGen = poller.generation(of: server.id)
        let secondGen = poller.generation(of: second.id)

        var changed = config!
        changed.servers[1].name = "Beta 2"
        poller.apply(changed)
        XCTAssertEqual(poller.generation(of: server.id), firstGen)
        XCTAssertNotEqual(poller.generation(of: second.id), secondGen)

        changed.servers.removeFirst()
        poller.apply(changed)
        XCTAssertNil(poller.generation(of: server.id))
        XCTAssertNil(poller.states[server.id])
    }

    func testIntervalChangeRestartsAll() {
        let poller = makePoller()
        let gen = poller.generation(of: server.id)
        var changed = config!
        changed.pollInterval = 60
        poller.apply(changed)
        XCTAssertNotEqual(poller.generation(of: server.id), gen)
    }

    func testURLChangeResetsToLoadingButNameChangeKeepsSnapshot() async {
        let poller = makePoller()
        let snap = AgentSnapshot.fixture()
        client.results = [.success(snap)]
        await poller.refresh(server.id)

        var renamed = config!
        renamed.servers[0].name = "Renamed"
        poller.apply(renamed)
        XCTAssertEqual(poller.states[server.id], .ok(snap, at: clock))

        var moved = renamed
        moved.servers[0].url = URL(string: "https://moved.example/metrics")!
        poller.apply(moved)
        XCTAssertEqual(poller.states[server.id], .loading)
    }

    func testResultFromBeforeConfigChangeIsDropped() async {
        let poller = makePoller()
        client.results = [.success(.fixture())]
        var release: CheckedContinuation<Void, Never>?
        client.gate = { await withCheckedContinuation { release = $0 } }
        let pending = Task { await poller.refresh(server.id) }
        while release == nil { await Task.yield() }

        var changed = config!
        changed.servers[0].url = URL(string: "https://other.example/metrics")!
        poller.apply(changed)
        release?.resume()
        await pending.value

        XCTAssertEqual(poller.states[server.id], .loading)
    }

    func testParkedServerIsNotFetchedAgain() async {
        let poller = makePoller()
        client.results = [.failure(.unauthorized), .success(.fixture())]
        await poller.refresh(server.id)
        let calls = client.calls.count
        await poller.refresh(server.id)
        XCTAssertEqual(client.calls.count, calls)
        XCTAssertEqual(poller.states[server.id], .error(.unauthorized))
    }

    func testRefreshNowSkipsParkedServers() async throws {
        let second = ServerConfig.fixture(name: "Beta", url: "https://b.example/metrics")
        config.servers.append(second)
        tokens.tokens[second.id] = "tok2"
        let poller = makePoller()
        client.results = [.failure(.unauthorized)]
        await poller.refresh(server.id)
        XCTAssertTrue(poller.isParked(server.id))
        let calls = client.calls.count
        client.results = [.success(.fixture())]
        poller.refreshNow()
        let deadline = Date().addingTimeInterval(2)
        while client.calls.count <= calls, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard client.calls.count > calls else {
            XCTFail("refreshNow never fetched the healthy server within 2s")
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let newCalls = client.calls.dropFirst(calls)
        XCTAssertEqual(newCalls.map(\.token), ["tok2"])
    }
}
