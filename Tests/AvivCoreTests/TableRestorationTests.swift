import XCTest

@testable import AvivCore

final class TableRestorationTests: XCTestCase {
    @MainActor
    func testLargeDocumentTableReturnsExactlyToNormalAfterClickAway() {
        let result = MarkdownTableRestorationVerifier.verify()

        XCTAssertTrue(result.passed, result.failures.joined(separator: "\n"))
        XCTAssertGreaterThan(result.documentLength, 12_000)
        XCTAssertGreaterThan(result.normalToEditingPixelDifference, 0)
        XCTAssertEqual(result.normalToRestoredPixelDifference, 0)
        XCTAssertEqual(result.maximumTableFrameDelta, 0, accuracy: 0.01)
        XCTAssertEqual(result.scrollOriginDelta, 0, accuracy: 0.01)
        XCTAssertTrue(result.sourcePreserved)
        XCTAssertTrue(result.selectionPreserved)
        XCTAssertTrue(result.attributesRestored)
        XCTAssertEqual(result.editedContentRestorationPixelDifference, 0)
        XCTAssertTrue(result.editedContentAttributesRestored)
    }
}
