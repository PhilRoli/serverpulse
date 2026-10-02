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
