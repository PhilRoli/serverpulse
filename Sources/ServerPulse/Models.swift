import Foundation

struct ServerConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var url: URL
    var sshTarget: String?
}

enum ContainerState: String, Codable, Equatable {
    case running, exited, paused, restarting, dead, created, removing, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ContainerState(rawValue: raw) ?? .unknown
    }
}

enum ContainerHealth: String, Codable, Equatable {
    case healthy, unhealthy, starting
}

struct Container: Codable, Equatable {
    var name: String
    var project: String?
    var state: ContainerState
    var health: ContainerHealth?
    var status: String

    private enum CodingKeys: String, CodingKey { case name, project, state, health, status }
}

// In an extension so the memberwise initializer is kept.
extension Container {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        state = (try? c.decode(ContainerState.self, forKey: .state)) ?? .unknown
        health = (try? c.decodeIfPresent(String.self, forKey: .health)).flatMap { ContainerHealth(rawValue: $0) }
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
    }
}

struct HostCPU: Codable, Equatable {
    var cores: Int?
    var pct: Double?
    var load1m: Double?

    private enum CodingKeys: String, CodingKey {
        case cores, pct
        case load1m = "load_1m"
    }
}

struct HostMemory: Codable, Equatable {
    var usedMb: Int?
    var totalMb: Int?

    var usedPct: Int? {
        guard let usedMb, let totalMb, totalMb > 0 else { return nil }
        return Int((Double(usedMb) * 100 / Double(totalMb)).rounded())
    }

    private enum CodingKeys: String, CodingKey {
        case usedMb = "used_mb"
        case totalMb = "total_mb"
    }
}

struct HostDisk: Codable, Equatable {
    var path: String?
    var usedPct: Int?

    private enum CodingKeys: String, CodingKey {
        case path
        case usedPct = "used_pct"
    }
}

/// Explicit snake_case keys: `.convertFromSnakeCase` would turn `load_1m` into `load1M`.
/// Host types are top-level (aliased here) to stay within SwiftLint's `nesting` rule.
struct AgentSnapshot: Codable, Equatable {
    typealias CPU = HostCPU
    typealias Memory = HostMemory
    typealias Disk = HostDisk

    var version: Int
    var hostname: String?
    var uptimeS: Int?
    var cpu: CPU
    var memory: Memory
    var disk: Disk
    var containers: [Container]?
    var dockerError: String?

    private enum CodingKeys: String, CodingKey {
        case version, hostname, cpu, memory, disk, containers
        case uptimeS = "uptime_s"
        case dockerError = "docker_error"
    }
}

enum MonitorError: Error, Equatable {
    case unauthorized
    case outdatedAgent
    case decoding
    case http(Int)
    case unreachable

    var label: String {
        switch self {
        case .unauthorized: return "Token rejected"
        case .outdatedAgent: return "Agent outdated"
        case .decoding: return "Bad response"
        case .http(let code): return "HTTP \(code)"
        case .unreachable: return "Unreachable"
        }
    }
}

enum ServerState: Equatable {
    case unconfigured
    case loading
    case ok(AgentSnapshot, at: Date)
    case stale(AgentSnapshot, at: Date, error: MonitorError)
    case error(MonitorError)

    var snapshot: AgentSnapshot? {
        switch self {
        case .ok(let snap, _), .stale(let snap, _, _): return snap
        default: return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

struct Thresholds: Equatable {
    var diskWarnPct: Int
    var memWarnPct: Int
}
