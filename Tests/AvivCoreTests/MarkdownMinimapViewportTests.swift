import XCTest
@testable import AvivCore

final class MarkdownMinimapViewportTests: XCTestCase {
    func testPureViewportProjectionPinsTopMiddleAndBottom() {
        let track = CGRect(x: 2, y: 0, width: 72, height: 600)
        let documentHeight: CGFloat = 2_400
        let visibleHeight: CGFloat = 600

        let top = MarkdownMinimapViewport.metrics(
            trackBounds: track,
            documentHeight: documentHeight,
            visibleRect: CGRect(x: 0, y: 0, width: 900, height: visibleHeight)
        )
        XCTAssertEqual(top.thumbRect.minY, track.minY, accuracy: 0.001)
        XCTAssertEqual(top.thumbRect.height, 150, accuracy: 0.001)

        let middle = MarkdownMinimapViewport.metrics(
            trackBounds: track,
            documentHeight: documentHeight,
            visibleRect: CGRect(x: 0, y: 900, width: 900, height: visibleHeight)
        )
        XCTAssertEqual(middle.thumbRect.minY, 225, accuracy: 0.001)
        XCTAssertEqual(middle.documentOffset(forThumbMinY: middle.thumbRect.minY), 900, accuracy: 0.001)

        let bottom = MarkdownMinimapViewport.metrics(
            trackBounds: track,
            documentHeight: documentHeight,
            visibleRect: CGRect(x: 0, y: 1_800, width: 900, height: visibleHeight)
        )
        XCTAssertEqual(bottom.thumbRect.maxY, track.maxY, accuracy: 0.001)
        XCTAssertEqual(bottom.documentOffset(forThumbMinY: bottom.thumbRect.minY), 1_800, accuracy: 0.001)
    }

    func testPureViewportProjectionHandlesVeryLongDocumentsWithCenteredMinimumThumb() {
        let metrics = MarkdownMinimapViewport.metrics(
            trackBounds: CGRect(x: 0, y: 0, width: 80, height: 640),
            documentHeight: 500_000,
            visibleRect: CGRect(x: 0, y: 250_000, width: 900, height: 500),
            minimumThumbHeight: 2
        )

        XCTAssertEqual(metrics.thumbRect.height, 2, accuracy: 0.001)
        XCTAssertEqual(metrics.thumbRect.midY, metrics.projectedY(forDocumentY: 250_250), accuracy: 0.75)
    }

    func testWorkspaceMinimapTracksRealScrollOffsetsAcrossFixtures() {
        let result = MarkdownMinimapVerifier.verify()
        XCTAssertTrue(result.passed, result.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(result.measuredPositions, 12)
    }
}
