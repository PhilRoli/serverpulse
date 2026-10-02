import Foundation
@testable import ServerPulse

extension Container {
    static func fixture(_ name: String, project: String? = nil, state: ContainerState = .running,
                        health: ContainerHealth? = nil) -> Container {
        Container(name: name, project: project, state: state, health: health, status: "Up 1 day")
    }
}

extension AgentSnapshot {
    static func fixture(containers: [Container]? = [], diskPct: Int? = 50, usedMb: Int? = 1000,
                        totalMb: Int? = 4000, dockerError: String? = nil) -> AgentSnapshot {
        AgentSnapshot(version: 2, hostname: "host", uptimeS: 100,
                      cpu: .init(cores: 2, pct: 12.5, load1m: 0.1),
                      memory: .init(usedMb: usedMb, totalMb: totalMb),
                      disk: .init(path: "/", usedPct: diskPct),
                      containers: containers, dockerError: dockerError)
    }
}

extension ServerConfig {
    static func fixture(name: String = "Alpha", url: String = "https://a.example/metrics") -> ServerConfig {
        ServerConfig(id: UUID(), name: name, url: URL(string: url)!, sshTarget: nil)
    }
}

/// Unique, self-cleaning UserDefaults suite for tests.
final class TestDefaults {
    let name = "ServerPulseTests-\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    func tearDown() { defaults.removePersistentDomain(forName: name) }
}

enum JSONFixtures {
    static let v2 = """
    {"version":2,"hostname":"rettstat-1","uptime_s":345600,
     "cpu":{"cores":2,"pct":12.5,"load_1m":0.14},
     "memory":{"used_mb":2072,"total_mb":3819},
     "disk":{"path":"/","used_pct":71},
     "containers":[{"name":"convex-backend-1","project":"convex","state":"running",
                    "health":"healthy","status":"Up 4 days (healthy)"}],
     "docker_error":null}
    """

    /// Shape served by the old Flask agent.
    static let v1 = """
    {"containers":[{"name":"web","status":"Up 2 days","running":true}],
     "cpu_load_1m":0.14,"memory":{"used_mb":3000,"total_mb":8192},"disk_pct":45}
    """
}
