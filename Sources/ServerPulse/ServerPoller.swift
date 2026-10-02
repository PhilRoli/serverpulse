import Foundation

@MainActor
final class ServerPoller {
    private struct Entry {
        var config: ServerConfig
        var generation: Int
        var task: Task<Void, Never>?
        var failures = 0
        var lastSnapshot: AgentSnapshot?
        var lastAt: Date?
        var parked = false
        var isRefreshing = false
    }

    private let client: MetricsFetching
    private let tokens: TokenStoring
    private let now: () -> Date
    private let startsLoops: Bool
    private var entries: [UUID: Entry] = [:]
    private var interval: TimeInterval = 30
    private var nextGeneration = 0

    private(set) var states: [UUID: ServerState] = [:]
    var onUpdate: ((UUID, ServerState) -> Void)?

    init(client: MetricsFetching, tokens: TokenStoring, now: @escaping () -> Date = { Date() },
         startsLoops: Bool = true) {
        self.client = client
        self.tokens = tokens
        self.now = now
        self.startsLoops = startsLoops
    }

    /// Restarts servers that are new, changed, or got a new token; all of them when the interval changed.
    func apply(_ config: AppConfig, tokenChanged: Set<UUID> = []) {
        let intervalChanged = config.pollInterval != interval
        interval = config.pollInterval
        let ids = Set(config.servers.map(\.id))
        for id in entries.keys where !ids.contains(id) {
            entries[id]?.task?.cancel()
            entries[id] = nil
            states[id] = nil
        }
        for server in config.servers {
            let old = entries[server.id]
            let changed = old?.config != server || tokenChanged.contains(server.id) || intervalChanged
            guard changed else { continue }
            old?.task?.cancel()
            nextGeneration += 1
            var entry = Entry(config: server, generation: nextGeneration)
            if let old, old.config.url == server.url {
                entry.lastSnapshot = old.lastSnapshot
                entry.lastAt = old.lastAt
            } else {
                publish(server.id, .loading)
            }
            entries[server.id] = entry
            if startsLoops { startLoop(server.id) }
        }
    }

    func refreshNow() {
        for (id, entry) in entries where !entry.parked {
            Task { await refresh(id) }
        }
    }

    func isParked(_ id: UUID) -> Bool { entries[id]?.parked ?? false }

    func generation(of id: UUID) -> Int? { entries[id]?.generation }

    func refresh(_ id: UUID) async {
        guard let entry = entries[id], !entry.isRefreshing, !entry.parked else { return }
        let generation = entry.generation
        entries[id]?.isRefreshing = true
        defer { if entries[id]?.generation == generation { entries[id]?.isRefreshing = false } }

        guard let token = await readToken(id) else {
            guard entries[id]?.generation == generation else { return }
            entries[id]?.parked = true
            publish(id, .unconfigured)
            return
        }
        do {
            let snapshot = try await client.fetch(url: entry.config.url, token: token)
            guard entries[id]?.generation == generation else { return }
            succeed(id, snapshot)
        } catch is CancellationError {
            return
        } catch {
            guard entries[id]?.generation == generation else { return }
            fail(id, error as? MonitorError ?? .unreachable)
        }
    }

    private func succeed(_ id: UUID, _ snapshot: AgentSnapshot) {
        let at = now()
        entries[id]?.failures = 0
        entries[id]?.lastSnapshot = snapshot
        entries[id]?.lastAt = at
        publish(id, .ok(snapshot, at: at))
    }

    private func fail(_ id: UUID, _ error: MonitorError) {
        if error == .unauthorized {
            entries[id]?.parked = true
            publish(id, .error(.unauthorized))
            return
        }
        if error == .offline { return }
        entries[id]?.failures += 1
        guard let entry = entries[id], entry.failures >= 2 else { return }
        if let snapshot = entry.lastSnapshot, let at = entry.lastAt {
            publish(id, .stale(snapshot, at: at, error: error))
        } else {
            publish(id, .error(error))
        }
    }

    private func publish(_ id: UUID, _ state: ServerState) {
        states[id] = state
        onUpdate?(id, state)
    }

    private func startLoop(_ id: UUID) {
        entries[id]?.task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(id)
                if Task.isCancelled || self.isParked(id) { return }
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    /// The Keychain read blocks (and may wait on a system prompt), so keep it off the main actor.
    private func readToken(_ id: UUID) async -> String? {
        let store = tokens
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: try? store.token(for: id))
            }
        }
    }
}
