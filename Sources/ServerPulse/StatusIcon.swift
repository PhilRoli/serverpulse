import AppKit

/// Menu bar icon + title styling. `contentTintColor` renders the whole status item black on current macOS,
/// so colour comes from a palette-coloured (non-template) symbol image instead.
enum StatusIcon {
    static func color(for tint: StatusTint) -> NSColor? {
        switch tint {
        case .normal: return nil
        case .red: return .systemRed
        case .orange: return .systemOrange
        }
    }

    static func image(for tint: StatusTint) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "ServerPulse") else {
            return nil
        }
        guard let color = color(for: tint) else {
            base.isTemplate = true
            return base
        }
        let tinted = base.withSymbolConfiguration(.init(paletteColors: [color])) ?? base
        tinted.isTemplate = false
        return tinted
    }

    static func titleAttributes(for tint: StatusTint) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]
        if let color = color(for: tint) { attributes[.foregroundColor] = color }
        return attributes
    }
}
