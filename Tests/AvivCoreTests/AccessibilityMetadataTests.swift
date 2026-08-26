import AppKit
import XCTest

@testable import AvivCore

final class AccessibilityMetadataTests: XCTestCase {
    @MainActor
    func testWorkspaceExposesRichDocumentAndOutlineMetadata() throws {
        let workspace = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 1_080, height: 760)
        )
        let window = NSWindow(
            contentRect: workspace.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = workspace
        workspace.updateDocumentTitle(
            url: URL(fileURLWithPath: "/tmp/Accessible Document.md"),
            isEdited: true
        )
        workspace.loadMarkdown(structuredFixture)
        workspace.layoutSubtreeIfNeeded()
        workspace.displayIfNeeded()

        XCTAssertEqual(workspace.accessibilityIdentifier(), "aviv.document.workspace")
        XCTAssertEqual(workspace.accessibilityRole(), .group)
        XCTAssertFalse((workspace.accessibilityHelp() ?? "").isEmpty)
        XCTAssertFalse((workspace.accessibilityValue() as? String ?? "").isEmpty)
        XCTAssertEqual(workspace.scrollView.accessibilityIdentifier(), "aviv.document.scroll-area")
        XCTAssertEqual(workspace.textView.accessibilityIdentifier(), "aviv.document.editor")
        XCTAssertEqual(workspace.textView.accessibilityRole(), .textArea)
        XCTAssertFalse((workspace.textView.accessibilityHelp() ?? "").isEmpty)

        let outline = workspace.minimapForTesting
        XCTAssertEqual(outline.accessibilityIdentifier(), "aviv.document.outline")
        XCTAssertEqual(outline.accessibilityRole(), .outline)
        XCTAssertFalse((outline.accessibilityLabel() ?? "").isEmpty)
        XCTAssertFalse((outline.accessibilityHelp() ?? "").isEmpty)
        XCTAssertEqual(outline.structureEntryCountForTesting > 0, true)
        XCTAssertEqual(outline.accessibilityOutlineItemCountForTesting, 5)

        let children = try XCTUnwrap(
            outline.accessibilityChildren() as? [NSAccessibilityElement]
        )
        XCTAssertEqual(children.count, 5)
        XCTAssertTrue(
            children.contains { $0.accessibilityIdentifier()?.contains("heading") == true }
        )
        XCTAssertTrue(children.contains { $0.accessibilityIdentifier()?.contains("table") == true })
        XCTAssertTrue(
            children.contains { $0.accessibilityIdentifier()?.contains("bullet") == true }
        )
        for child in children {
            XCTAssertEqual(child.accessibilityRole(), .row)
            XCTAssertFalse((child.accessibilityIdentifier() ?? "").isEmpty)
            XCTAssertFalse((child.accessibilityLabel() ?? "").isEmpty)
            XCTAssertFalse((child.accessibilityHelp() ?? "").isEmpty)
            XCTAssertFalse((child.accessibilityValue() as? String ?? "").isEmpty)
        }

        let table = try XCTUnwrap(
            children.first { $0.accessibilityIdentifier()?.contains(".table.") == true }
        )
        XCTAssertTrue(table.accessibilityPerformPress())
        XCTAssertEqual(
            workspace.textView.selectedRange().location,
            (structuredFixture as NSString).range(of: "| Field | Value |").location
        )
    }

    @MainActor
    func testRemoteIndicatorExposesPhaseSourceWritableStateAndHelp() {
        let indicator = RemoteSyncIndicatorView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        indicator.update(
            RemoteSyncPresentation(
                phase: .conflict,
                sourceHost: "pitchai.net",
                isWritable: true,
                detail: "Incoming edits waiting"
            ),
            theme: .clean
        )

        XCTAssertEqual(indicator.accessibilityIdentifier(), "remote-source-badge")
        XCTAssertEqual(indicator.accessibilityRole(), .group)
        XCTAssertEqual(indicator.accessibilityLabel(), "Live document")
        XCTAssertTrue((indicator.accessibilityValue() as? String)?.contains("conflict") == true)
        XCTAssertTrue((indicator.accessibilityValue() as? String)?.contains("writable") == true)
        XCTAssertTrue(indicator.accessibilityHelp()?.contains("pitchai.net") == true)
        XCTAssertFalse(indicator.isAccessibilityHidden())
    }

    @MainActor
    func testSearchMatchesMarkOutlineSectionsWithoutChangingDocumentGeometry() throws {
        let workspace = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 680)
        )
        let window = NSWindow(
            contentRect: workspace.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = workspace
        let markdown = """
            # Planning

            Search target is inside Planning.

            ## Details

            - Another target is in this row.

            # Appendix

            No match here.
            """ + "\n"
        workspace.loadMarkdown(markdown)
        workspace.layoutSubtreeIfNeeded()
        let textContainerWidth = workspace.resolvedTextContainerWidthForTesting
        let textFrame = workspace.textView.frame

        let matches = MarkdownSearchIndex.findMatches(in: markdown, query: "target")
        workspace.updateSearchMatches(matches)
        workspace.displayIfNeeded()

        XCTAssertEqual(workspace.outlineSearchHitCountForTesting, 3)
        XCTAssertTrue(
            workspace.outlineSearchHitIdentifiersForTesting.contains {
                $0.contains("heading.line-1")
            }
        )
        XCTAssertEqual(workspace.outlineSearchHitFramesForTesting.count, 3)
        XCTAssertEqual(workspace.resolvedTextContainerWidthForTesting, textContainerWidth)
        XCTAssertEqual(workspace.textView.frame, textFrame)

        let children = try XCTUnwrap(
            workspace.minimapForTesting.accessibilityChildren() as? [NSAccessibilityElement]
        )
        let matchedChildren = children.filter {
            ($0.accessibilityValue() as? String)?.contains("contains search matches") == true
        }
        XCTAssertEqual(matchedChildren.count, 3)
        XCTAssertTrue(
            matchedChildren.allSatisfy {
                $0.accessibilityHelp()?.contains("contains search matches") == true
            }
        )

        workspace.updateSearchMatches([])
        XCTAssertEqual(workspace.outlineSearchHitCountForTesting, 0)
        XCTAssertFalse(
            children.contains {
                ($0.accessibilityValue() as? String)?.contains("contains search matches") == true
            }
        )
    }

    private var structuredFixture: String {
        """
        # Accessible heading

        - Bullet item
        1. Numbered item
        - [ ] Task item

        | Field | Value |
        | --- | --- |
        | Sidebar | Reliable |
        """ + "\n"
    }
}
