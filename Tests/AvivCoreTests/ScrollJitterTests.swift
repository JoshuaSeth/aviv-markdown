import XCTest

@testable import AvivCore

final class ScrollJitterTests: XCTestCase {
    @MainActor
    func testTypingDoesNotJitterScrollPositionOrMinimapThumb() {
        let result = MarkdownScrollJitterVerifier.verify()
        XCTAssertTrue(result.passed, result.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(result.measuredEdits, 24)
    }
}
