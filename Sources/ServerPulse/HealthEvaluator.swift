import Foundation

struct Issue: Equatable {
    enum Kind: String {
        case containerDown, containerUnhealthy, diskHigh, memHigh
        case agentUnreachable, authFailed, agentOutdated, dockerUnavailable
    }

    var serverID: UUID
    var serverName: String
    var kind: Kind
    var subject: String?
    var value: Int?

    static func key(_ kind: Kind, _ subject: String? = nil) -> String { "\(kind.rawValue):\(subject ?? "")" }

    /// Stable identity for diffing; `value` is deliberately excluded.
    var key: String { Self.key(kind, subject) }

    var isAgentLevel: Bool {
        switch kind {
        case .agentUnreachable, .authFailed, .agentOutdated, .dockerUnavailable: return true
        case .containerDown, .containerUnhealthy, .diskHigh, .memHigh: return false
        }
    }

    /// Derived from snapshot contents rather than from the agent connection.
    var isSnapshotDerived: Bool { !isAgentLevel }
}

enum HealthEvaluator {
    /// An active disk/RAM issue stays active until the value drops this many points below the threshold.
    static let hysteresis = 5

    static func issues(server: ServerConfig, state: ServerState, thresholds: Thresholds,
                       active: Set<String> = []) -> [Issue] {
        let make = { (kind: Issue.Kind, subject: String?, value: Int?) in
            Issue(serverID: server.id, serverName: server.name, kind: kind, subject: subject, value: value)
        }
        if server.lanOnly && state.isUnreachable { return [] }
        switch state {
        case .unconfigured, .loading:
            return []
        case .error(let error):
            return [make(connectionKind(error), nil, nil)]
        case .stale(let snapshot, _, let error):
            return [make(connectionKind(error), nil, nil)] + snapshotIssues(snapshot, thresholds, active, make)
        case .ok(let snapshot, _):
            return snapshotIssues(snapshot, thresholds, active, make)
        }
    }

    private static func connectionKind(_ error: MonitorError) -> Issue.Kind {
        switch error {
        case .unauthorized: return .authFailed
        case .outdatedAgent: return .agentOutdated
        case .decoding, .http, .unreachable, .offline: return .agentUnreachable
        }
    }

    private static func snapshotIssues(_ snapshot: AgentSnapshot, _ thresholds: Thresholds, _ active: Set<String>,
                                       _ make: (Issue.Kind, String?, Int?) -> Issue) -> [Issue] {
        var result: [Issue] = []
        if let containers = snapshot.containers {
            for container in containers.sorted(by: { $0.name < $1.name }) {
                if container.state == .exited || container.state == .dead {
                    result.append(make(.containerDown, container.name, nil))
                } else if container.health == .unhealthy {
                    result.append(make(.containerUnhealthy, container.name, nil))
                }
            }
        } else {
            result.append(make(.dockerUnavailable, nil, nil))
        }
        if let disk = snapshot.disk.usedPct,
           isOver(disk, thresholds.diskWarnPct, wasActive: active.contains(Issue.key(.diskHigh))) {
            result.append(make(.diskHigh, nil, disk))
        }
        if let mem = snapshot.memory.usedPct,
           isOver(mem, thresholds.memWarnPct, wasActive: active.contains(Issue.key(.memHigh))) {
            result.append(make(.memHigh, nil, mem))
        }
        return result
    }

    private static func isOver(_ value: Int, _ threshold: Int, wasActive: Bool) -> Bool {
        value >= (wasActive ? threshold - hysteresis : threshold)
    }
}
