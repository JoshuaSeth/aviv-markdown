import XCTest
@testable import AvivCore

final class TypingPerformanceTests: XCTestCase {
    func testLargeDocumentTypingStaysInteractive() {
        let result = MarkdownTypingPerformanceVerifier.verify()
        XCTAssertTrue(result.passed, result.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(result.editCount, 48)
        XCTAssertGreaterThan(result.documentLength, 90_000)
    }
}
