import AppKit
import XCTest
@testable import ServerPulse

final class StatusIconTests: XCTestCase {
    func testNormalUsesTemplateImageAndNoForegroundColor() throws {
        let image = try XCTUnwrap(StatusIcon.image(for: .normal))
        XCTAssertTrue(image.isTemplate)
        let attributes = StatusIcon.titleAttributes(for: .normal)
        XCTAssertNotNil(attributes[.font])
        XCTAssertNil(attributes[.foregroundColor])
    }

    func testRedUsesColouredNonTemplateImage() throws {
        let image = try XCTUnwrap(StatusIcon.image(for: .red))
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(StatusIcon.titleAttributes(for: .red)[.foregroundColor] as? NSColor, .systemRed)
    }

    func testOrangeUsesColouredNonTemplateImage() throws {
        let image = try XCTUnwrap(StatusIcon.image(for: .orange))
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(StatusIcon.titleAttributes(for: .orange)[.foregroundColor] as? NSColor, .systemOrange)
    }
}
