import AppKit
import MenuBarKit
import XCTest
@testable import ServerPulse

@MainActor
final class PreferencesVersionTests: XCTestCase {
    private func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { sub -> [NSTextField] in
            let nested = textFields(in: sub)
            if let field = sub as? NSTextField { return [field] + nested }
            return nested
        }
    }

    func testShowsVersionLineInsideTheWindow() throws {
        let controller = PreferencesWindowController(
            config: AppConfig(), tokens: FakeTokens(), client: FakeClient(),
            loginItem: LoginItemController(manager: NoLoginItem())
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        let version = try XCTUnwrap(textFields(in: content).first {
            $0.stringValue.hasPrefix("Version") || $0.stringValue == "Development build"
        })
        content.layoutSubtreeIfNeeded()
        XCTAssertTrue(content.bounds.insetBy(dx: -1, dy: -1).contains(version.convert(version.bounds, to: content)))
    }
}

private final class NoLoginItem: LoginItemManaging {
    var isEnabled = false
    func register() throws {}
    func unregister() throws {}
}
