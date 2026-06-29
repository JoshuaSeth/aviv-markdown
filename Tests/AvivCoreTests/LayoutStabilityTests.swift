import XCTest
@testable import AvivCore

final class LayoutStabilityTests: XCTestCase {
    func testCursorMovementDoesNotMoveRenderedContentOrChangeContentStyle() {
        let result = MarkdownLayoutVerifier.verify()
        XCTAssertTrue(result.passed, result.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(result.measuredSelections, 10)
    }
}
