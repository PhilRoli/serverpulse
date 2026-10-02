import Foundation

struct AlertEvent: Equatable {
    enum Change: Equatable {
        case raised, resolved
    }

    var change: Change
    var issue: Issue
}

struct AlertTracker {
    private var previous: [UUID: [String: Issue]] = [:]

    func activeKeys(for serverID: UUID) -> Set<String> {
        Set((previous[serverID] ?? [:]).keys)
    }

    /// The first update per server is a silent baseline. `containers` holds the names in the current snapshot
    /// (nil without one): snapshot-derived resolutions are only trusted with a snapshot, and container ones only
    /// while the container still exists, so a removed container never reports "back up".
    mutating func update(serverID: UUID, issues: [Issue], containers: Set<String>?) -> [AlertEvent] {
        var current: [String: Issue] = [:]
        for issue in issues where current[issue.key] == nil {
            current[issue.key] = issue
        }
        defer { previous[serverID] = current }
        guard let before = previous[serverID] else { return [] }

        let raised = current.keys.filter { before[$0] == nil }.sorted()
            .compactMap { current[$0] }
            .map { AlertEvent(change: .raised, issue: $0) }
        let resolved = before.keys.filter { current[$0] == nil }.sorted()
            .compactMap { before[$0] }
            .filter { Self.trustsResolution(of: $0, containers: containers) }
            .map { AlertEvent(change: .resolved, issue: $0) }
        return raised + resolved
    }

    mutating func remove(serverID: UUID) {
        previous[serverID] = nil
    }

    private static func trustsResolution(of issue: Issue, containers: Set<String>?) -> Bool {
        if issue.kind == .dockerUnavailable { return containers != nil }
        guard issue.isSnapshotDerived else { return true }
        guard let containers else { return false }
        switch issue.kind {
        case .containerDown, .containerUnhealthy:
            return issue.subject.map(containers.contains) ?? false
        default:
            return true
        }
    }
}
