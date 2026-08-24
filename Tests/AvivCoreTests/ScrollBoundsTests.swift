import XCTest

@testable import AvivCore

final class ScrollBoundsTests: XCTestCase {
    @MainActor
    func testEditorCanReturnCompletelyToTopWithoutHiddenInsets() {
        let result = MarkdownScrollBoundsVerifier.verify()
        XCTAssertTrue(result.passed, result.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(result.measuredFixtures, 3)
    }
}
