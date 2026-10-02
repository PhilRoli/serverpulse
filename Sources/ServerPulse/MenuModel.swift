import Foundation

enum Dot: Int, Comparable {
    case green, grey, orange, red

    static func < (lhs: Dot, rhs: Dot) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ContainerRow: Equatable {
    var name: String
    var dot: Dot
    var status: String
}

struct MetricSegment: Equatable {
    var text: String
    var high: Bool
}

enum MenuRow: Equatable {
    case header(name: String, updatedAt: Date?, stale: Bool)
    case metrics([MetricSegment])
    case group(name: String, dot: Dot, children: [ContainerRow])
    case container(ContainerRow)
    case message(String)
    case ssh(target: String)
    case addServer
    case separator
}

/// Value-type description of the dropdown; StatusBarController only renders it.
enum MenuModel {
    static func rows(servers: [ServerConfig], states: [UUID: ServerState], thresholds: Thresholds) -> [MenuRow] {
        guard !servers.isEmpty else { return [.addServer] }
        var rows: [MenuRow] = []
        for (index, server) in servers.enumerated() {
            if index > 0 { rows.append(.separator) }
            rows += section(server, states[server.id] ?? .loading, thresholds)
        }
        return rows
    }

    static func dot(for container: Container) -> Dot {
        switch container.state {
        case .exited, .dead: return .red
        case .paused, .restarting: return .orange
        case .created, .removing, .unknown: return .grey
        case .running: return container.health == .unhealthy || container.health == .starting ? .orange : .green
        }
    }

    private static func section(_ server: ServerConfig, _ state: ServerState, _ thresholds: Thresholds) -> [MenuRow] {
        var rows: [MenuRow]
        switch state {
        case .unconfigured:
            rows = [.header(name: server.name, updatedAt: nil, stale: false), .message("No token")]
        case .loading:
            rows = [.header(name: server.name, updatedAt: nil, stale: false), .message("Connecting…")]
        case .error(let error):
            rows = [.header(name: server.name, updatedAt: nil, stale: false), .message("⚠︎ \(error.label)")]
        case .ok(let snapshot, let at):
            rows = [.header(name: server.name, updatedAt: at, stale: false)] + body(snapshot, thresholds)
        case .stale(let snapshot, let at, _):
            rows = [.header(name: server.name, updatedAt: at, stale: true)] + body(snapshot, thresholds)
        }
        if let target = server.sshTarget, !target.isEmpty { rows.append(.ssh(target: target)) }
        return rows
    }

    private static func body(_ snapshot: AgentSnapshot, _ thresholds: Thresholds) -> [MenuRow] {
        let metrics = MenuRow.metrics(segments(snapshot, thresholds))
        guard let containers = snapshot.containers else { return [metrics, .message("⚠︎ Docker unavailable")] }
        guard !containers.isEmpty else { return [metrics, .message("No containers")] }
        return [metrics] + containerRows(containers)
    }

    private static func segments(_ snapshot: AgentSnapshot, _ thresholds: Thresholds) -> [MetricSegment] {
        let memory = snapshot.memory
        let ram = Format.gigabytes(usedMB: memory.usedMb, totalMB: memory.totalMb)
        return [
            MetricSegment(text: "CPU \(Format.percent(snapshot.cpu.pct))", high: false),
            MetricSegment(text: "RAM \(ram)", high: (memory.usedPct ?? 0) >= thresholds.memWarnPct),
            MetricSegment(text: "Disk \(Format.percent(snapshot.disk.usedPct))",
                          high: (snapshot.disk.usedPct ?? 0) >= thresholds.diskWarnPct)
        ]
    }

    /// Compose projects with 2+ containers become submenus (sorted by name); everything else is listed flat after.
    private static func containerRows(_ containers: [Container]) -> [MenuRow] {
        let row = { (c: Container) in ContainerRow(name: c.name, dot: dot(for: c), status: c.status) }
        var flat = containers.filter { $0.project == nil }.map(row)
        var groups: [MenuRow] = []
        let byProject = Dictionary(grouping: containers.filter { $0.project != nil }, by: { $0.project ?? "" })
        for name in byProject.keys.sorted() {
            let members = (byProject[name] ?? []).sorted { $0.name < $1.name }.map(row)
            if members.count == 1 {
                flat += members
            } else {
                groups.append(.group(name: name, dot: members.map(\.dot).max() ?? .green, children: members))
            }
        }
        return groups + flat.sorted { $0.name < $1.name }.map(MenuRow.container)
    }
}
