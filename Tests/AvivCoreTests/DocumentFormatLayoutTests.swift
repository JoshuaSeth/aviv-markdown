import AppKit
import XCTest
@testable import AvivCore

final class DocumentFormatLayoutTests: XCTestCase {
    func testDocumentFormatsUseExpectedScreenWidths() {
        let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: 1180, height: 920))
        workspace.loadMarkdown(MarkdownSamples.starter)

        workspace.documentFormat = .blog
        workspace.layoutSubtreeIfNeeded()
        XCTAssertEqual(workspace.resolvedTextContainerWidthForTesting, 820, accuracy: 1.0)

        workspace.documentFormat = .a4
        workspace.layoutSubtreeIfNeeded()
        XCTAssertEqual(workspace.resolvedTextContainerWidthForTesting, 930, accuracy: 1.0)
        XCTAssertGreaterThan(930, 820)
    }

    func testA4PrintViewUsesPaperContentWidthWithoutEditorInsets() {
        let margins = MarkdownDocumentFormat.a4.printMargins
        let printableWidth = MarkdownDocumentFormat.a4.paperSize.width - margins.left - margins.right
        let printView = MarkdownPrintView(
            markdown: MarkdownSamples.starter,
            printableWidth: printableWidth,
            format: .a4
        )

        printView.layoutSubtreeIfNeeded()
        XCTAssertEqual(printView.textView.textContainerInset.width, 0, accuracy: 0.01)
        XCTAssertEqual(printView.textView.textContainer?.containerSize.width ?? 0, printableWidth, accuracy: 0.01)
        XCTAssertGreaterThan(printView.frame.height, 200)
    }
}
