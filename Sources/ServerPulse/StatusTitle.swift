import Foundation

enum StatusTint: Equatable {
    case normal, red, orange
}

struct StatusTitle: Equatable {
    var text: String
    var tint: StatusTint

    static func make(issues: [Issue], anyStale: Bool) -> StatusTitle {
        var title: StatusTitle
        if issues.contains(where: { !$0.isAgentLevel }) {
            title = StatusTitle(text: "\(issues.count)", tint: .red)
        } else if !issues.isEmpty {
            title = StatusTitle(text: "!", tint: .orange)
        } else {
            title = StatusTitle(text: "", tint: .normal)
        }
        if anyStale { title.text += "*" }
        return title
    }
}
