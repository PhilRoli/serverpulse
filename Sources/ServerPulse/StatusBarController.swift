import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onRefresh: (() -> Void)?
    var onPreferences: (() -> Void)?
    var rows: () -> [MenuRow] = { [] }
    var now: () -> Date = { Date() }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private struct Header {
        let item: NSMenuItem
        let name: String
        let updatedAt: Date?
        let stale: Bool
    }

    private var headers: [Header] = []
    private var ticker: Timer?

    override init() {
        super.init()
        statusItem.button?.image = StatusIcon.image(for: .normal)
        statusItem.button?.imagePosition = .imageLeading
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func setTitle(_ title: StatusTitle) {
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(for: title.tint)
        button.attributedTitle = NSAttributedString(
            string: title.text.isEmpty ? "" : " \(title.text)",
            attributes: StatusIcon.titleAttributes(for: title.tint))
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    /// Menus run the event loop in `.eventTracking` mode, so the ticker must be scheduled in `.common`.
    func menuWillOpen(_ menu: NSMenu) {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickHeaders() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Building

    private func rebuild() {
        menu.removeAllItems()
        headers = []
        rows().forEach { menu.addItem(item(for: $0)) }
        menu.addItem(.separator())
        menu.addItem(action("Refresh Now", #selector(refresh), key: "r"))
        menu.addItem(action("Preferences…", #selector(preferences), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(for row: MenuRow) -> NSMenuItem {
        switch row {
        case let .header(name, updatedAt, stale):
            let item = info(headerTitle(name: name, updatedAt: updatedAt, stale: stale), indent: 0)
            headers.append(Header(item: item, name: name, updatedAt: updatedAt, stale: stale))
            return item
        case .metrics(let segments):
            return info(metricsTitle(segments))
        case let .group(name, dot, children):
            let item = info(dotTitle(dot, "\(name) (\(children.count))"))
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            children.forEach { submenu.addItem(info(dotTitle($0.dot, $0.name, detail: $0.status), indent: 0)) }
            item.submenu = submenu
            return item
        case .container(let row):
            let item = info(dotTitle(row.dot, row.name))
            item.toolTip = row.status
            return item
        case .message(let text):
            return info(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        case .ssh(let target):
            let item = action("Open SSH", #selector(openSSH(_:)))
            item.representedObject = target
            item.indentationLevel = 1
            return item
        case .addServer:
            return action("Add a server…", #selector(preferences))
        case .separator:
            return .separator()
        }
    }

    /// Enabled but action-less, so colours aren't dimmed the way disabled items are.
    private func info(_ title: NSAttributedString, indent: Int = 1) -> NSMenuItem {
        let item = NSMenuItem(title: title.string, action: nil, keyEquivalent: "")
        item.attributedTitle = title
        item.indentationLevel = indent
        item.isEnabled = true
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func tickHeaders() {
        for header in headers {
            header.item.attributedTitle = headerTitle(name: header.name, updatedAt: header.updatedAt,
                                                      stale: header.stale)
        }
    }

    // MARK: Titles

    private func headerTitle(name: String, updatedAt: Date?, stale: Bool) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 300)]
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13), .paragraphStyle: style
        ])
        var trailing = updatedAt.map { Format.age(since: $0, now: now()) } ?? ""
        if stale { trailing = trailing.isEmpty ? "⚠︎ stale" : "⚠︎ stale · \(trailing)" }
        if !trailing.isEmpty {
            title.append(NSAttributedString(string: "\t\(trailing)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: stale ? NSColor.systemOrange : NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]))
        }
        return title
    }

    private func metricsTitle(_ segments: [MetricSegment]) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let title = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: " · ", attributes: [
                    .font: font, .foregroundColor: NSColor.tertiaryLabelColor
                ]))
            }
            title.append(NSAttributedString(string: segment.text, attributes: [
                .font: font, .foregroundColor: segment.high ? NSColor.systemRed : NSColor.secondaryLabelColor
            ]))
        }
        return title
    }

    private func dotTitle(_ dot: Dot, _ text: String, detail: String? = nil) -> NSAttributedString {
        let color: NSColor = switch dot {
        case .green: .systemGreen
        case .grey: .systemGray
        case .orange: .systemOrange
        case .red: .systemRed
        }
        let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: color])
        title.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        if let detail {
            title.append(NSAttributedString(string: "   \(detail)", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        return title
    }

    // MARK: Actions

    @objc private func refresh() { onRefresh?() }

    @objc private func preferences() { onPreferences?() }

    @objc private func openSSH(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String, let url = URL(string: "ssh://\(target)") else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }
}
