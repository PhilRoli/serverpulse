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

struct AgentSnapshot: Codable, Equatable {
    struct CPU: Codable, Equatable {
        var cores: Int?
        var pct: Double?
        var load1m: Double?

        private enum CodingKeys: String, CodingKey {
            case cores, pct
            case load1m = "load_1m"
        }
    }

    struct Memory: Codable, Equatable {
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

    struct Disk: Codable, Equatable {
        var path: String?
        var usedPct: Int?

        private enum CodingKeys: String, CodingKey {
            case path
            case usedPct = "used_pct"
        }
    }

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

// In extensions so the memberwise initializers are kept.
extension AgentSnapshot.CPU {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cores = try values.decodeIfPresent(Int.self, forKey: .cores)
        pct = try values.decodeIfPresent(Double.self, forKey: .pct)
        load1m = try values.decodeIfPresent(Double.self, forKey: .load1m)
    }
}

extension AgentSnapshot.Memory {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        usedMb = try values.decodeIfPresent(Int.self, forKey: .usedMb)
        totalMb = try values.decodeIfPresent(Int.self, forKey: .totalMb)
    }
}

extension AgentSnapshot.Disk {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decodeIfPresent(String.self, forKey: .path)
        usedPct = try values.decodeIfPresent(Int.self, forKey: .usedPct)
    }
}

extension AgentSnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        hostname = try values.decodeIfPresent(String.self, forKey: .hostname)
        uptimeS = try values.decodeIfPresent(Int.self, forKey: .uptimeS)
        cpu = try values.decode(CPU.self, forKey: .cpu)
        memory = try values.decode(Memory.self, forKey: .memory)
        disk = try values.decode(Disk.self, forKey: .disk)
        containers = try values.decodeIfPresent([Container].self, forKey: .containers)
        dockerError = try values.decodeIfPresent(String.self, forKey: .dockerError)
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
