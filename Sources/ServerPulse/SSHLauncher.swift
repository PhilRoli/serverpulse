import AppKit

/// Terminal apps selectable for "Open SSH". Terminal and iTerm2 handle `ssh://` URLs themselves;
/// Ghostty doesn't, so it is launched with `-e ssh <target>` instead.
enum SSHTerminal: String, CaseIterable {
    case terminal = "com.apple.Terminal"
    case iterm = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        case .ghostty: return "Ghostty"
        }
    }

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) }

    static var installed: [SSHTerminal] { allCases.filter { $0.appURL != nil } }
}

enum SSHLaunch: Equatable {
    case url(URL, app: SSHTerminal?)
    case process(executable: String, arguments: [String])
}

enum SSHLauncher {
    /// What to run for `target` in the given terminal; `nil` means the system default `ssh://` handler.
    static func plan(target: String, terminal: SSHTerminal?) -> SSHLaunch? {
        guard let url = URL(string: "ssh://\(target)") else { return nil }
        switch terminal {
        case .ghostty?:
            return .process(executable: "/usr/bin/open",
                            arguments: ["-n", "-b", SSHTerminal.ghostty.rawValue, "--args", "-e", "ssh", target])
        case let app?:
            return .url(url, app: app)
        case nil:
            return .url(url, app: nil)
        }
    }

    @MainActor
    static func open(target: String, bundleID: String?) {
        // An unknown or uninstalled app falls back to the system default.
        let terminal = bundleID.flatMap(SSHTerminal.init(rawValue:)).flatMap { $0.appURL == nil ? nil : $0 }
        switch plan(target: target, terminal: terminal) {
        case .url(let url, let app)?:
            if let appURL = app?.appURL {
                NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                        configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        case .process(let executable, let arguments)?:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            do { try process.run() } catch { NSSound.beep() }
        case nil:
            NSSound.beep()
        }
    }
}
