import Foundation
import MenuBarKit

struct AppConfig: Codable, Equatable {
    static let intervals: [TimeInterval] = [15, 30, 60, 120]
    static let warnChoices: [Int] = [70, 75, 80, 85, 90, 95]

    var servers: [ServerConfig] = []
    var pollInterval: TimeInterval = 30
    var diskWarnPct: Int = 85
    var memWarnPct: Int = 90
    var notificationsEnabled: Bool = true

    var thresholds: Thresholds { Thresholds(diskWarnPct: diskWarnPct, memWarnPct: memWarnPct) }

    private enum CodingKeys: String, CodingKey {
        case servers, pollInterval, diskWarnPct, memWarnPct, notificationsEnabled
    }
}

// In an extension so the memberwise/default initializer is kept.
extension AppConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = AppConfig()
        servers = try c.decodeIfPresent([ServerConfig].self, forKey: .servers) ?? base.servers
        pollInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .pollInterval) ?? base.pollInterval
        diskWarnPct = try c.decodeIfPresent(Int.self, forKey: .diskWarnPct) ?? base.diskWarnPct
        memWarnPct = try c.decodeIfPresent(Int.self, forKey: .memWarnPct) ?? base.memWarnPct
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)
            ?? base.notificationsEnabled
    }
}

extension AppConfig: DefaultInitializable {}
typealias AppConfigStore = JSONDefaultsStore<AppConfig>
