import Foundation

enum Format {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }

    static func percent(_ value: Int?) -> String {
        guard let value else { return "–" }
        return "\(value)%"
    }

    static func gigabytes(usedMB: Int?, totalMB: Int?) -> String {
        guard let usedMB, let totalMB else { return "–" }
        let used = String(format: "%.1f", Double(usedMB) / 1024)
        let total = String(format: "%.1f", Double(totalMB) / 1024)
        return "\(used)/\(total) GB"
    }

    static func age(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds)s ago"
        case ..<3_600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3_600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }
}
