import AppKit
import XCTest

@testable import AvivCore

final class RemoteExternalUpdateLayoutTests: XCTestCase {
    @MainActor
    func testIncomingInsertionPreservesCaretViewportAndContainerGeometry() {
        let original = fixture(prefix: "Original")
        let incoming = original.replacingOccurrences(
            of: "Line 0200",
            with: "External line A\nExternal line B\nLine 0200"
        )
        let workspace = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 1040, height: 740)
        )
        workspace.loadMarkdown(original)
        workspace.layoutSubtreeIfNeeded()
        let caret = (original as NSString).range(of: "Line 0700").location
        workspace.textView.setSelectedRange(NSRange(location: caret, length: 0))
        workspace.textView.scrollRangeToVisible(NSRange(location: caret, length: 0))
        workspace.layoutSubtreeIfNeeded()

        let plan = RemoteMarkdownChangePlan(oldMarkdown: original, newMarkdown: incoming)
        let result = workspace.applyExternalMarkdown(incoming, using: plan)
        workspace.layoutSubtreeIfNeeded()

        let mappedCaret = workspace.textView.selectedRange().location
        XCTAssertEqual((incoming as NSString).substring(from: mappedCaret).prefix(9), "Line 0700")
        XCTAssertEqual(result.visibleAnchorDelta, 0, accuracy: 0.5)
        XCTAssertEqual(result.textContainerWidthDelta, 0, accuracy: 0.01)
        XCTAssertFalse(result.mappedSelections.isEmpty)
        XCTAssertGreaterThan(workspace.remoteChangedLineCountForTesting, 0)
    }

    @MainActor
    func testSixRemoteIndicatorsDoNotChangeEditorGeometry() {
        let workspace = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 1040, height: 740)
        )
        workspace.loadMarkdown(fixture(prefix: "Indicators"))
        workspace.layoutSubtreeIfNeeded()
        let widthBefore = workspace.resolvedTextContainerWidthForTesting
        let originBefore = workspace.scrollView.contentView.bounds.origin

        workspace.updateRemoteSyncPresentation(
            RemoteSyncPresentation(
                phase: .incomingApplied,
                sourceHost: "pitchai.net",
                isWritable: true,
                detail: "External edit applied"
            )
        )
        workspace.announceRemoteChange(
            lineRanges: [NSRange(location: 12, length: 10)],
            message: "External edits applied"
        )
        workspace.layoutSubtreeIfNeeded()

        let identifiers = workspace.remoteIndicatorIdentifiersForTesting
        XCTAssertGreaterThanOrEqual(Set(identifiers).count, 5)
        XCTAssertEqual(workspace.resolvedTextContainerWidthForTesting, widthBefore, accuracy: 0.01)
        XCTAssertEqual(
            workspace.scrollView.contentView.bounds.origin.x,
            originBefore.x,
            accuracy: 0.01
        )
        XCTAssertEqual(
            workspace.scrollView.contentView.bounds.origin.y,
            originBefore.y,
            accuracy: 0.01
        )
    }

    private func fixture(prefix: String) -> String {
        var lines = ["# \(prefix)", ""]
        for index in 0..<1_000 {
            lines.append(String(format: "Line %04d has stable remote-sync content.", index))
        }
        return lines.joined(separator: "\n")
    }
}
