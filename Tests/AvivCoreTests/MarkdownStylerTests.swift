import AppKit
import XCTest
@testable import AvivCore

final class MarkdownStylerTests: XCTestCase {
    func testHeadingSyntaxIsSuppressedButContentIsStyled() {
        let markdown = "# Title\n\nBody"
        let attributed = MarkdownStyler().attributedString(for: markdown, selectedRanges: [NSRange(location: 9, length: 0)])

        let syntaxColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(syntaxColor?.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1, 0, accuracy: 0.001)
        let syntaxFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertLessThan(syntaxFont?.pointSize ?? 1, 1)

        let titleFont = attributed.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(titleFont?.pointSize ?? 0, MarkdownTheme.clean.bodyFont.pointSize)
    }

    func testActiveHeadingHasNonLayoutAnnotationTokenWithoutChangingContentStyle() {
        let markdown = "# Title\n\nBody"
        let styler = MarkdownStyler()
        let inactive = styler.attributedString(for: markdown, selectedRanges: [NSRange(location: 9, length: 0)])
        let active = styler.attributedString(for: markdown, selectedRanges: [NSRange(location: 3, length: 0)])

        let inactiveSyntax = inactive.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let activeSyntax = active.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(inactiveSyntax?.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(activeSyntax?.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1, 0, accuracy: 0.001)

        XCTAssertEqual(fontKey(inactive, at: 2), fontKey(active, at: 2))
        XCTAssertEqual(colorKey(inactive, at: 2), colorKey(active, at: 2))

        let tokens = MarkdownAnnotationParser.tokens(in: markdown, selectedRanges: [NSRange(location: 3, length: 0)])
        XCTAssertTrue(tokens.contains(MarkdownAnnotationToken(range: NSRange(location: 0, length: 1), label: "#", role: .heading)))
    }

    func testInlineSyntaxIsSuppressedAndActiveLineProducesAnnotations() {
        let markdown = "A **bold** word\nSecond line"
        let inactive = MarkdownStyler().attributedString(for: markdown, selectedRanges: [NSRange(location: 20, length: 0)])
        let active = MarkdownStyler().attributedString(for: markdown, selectedRanges: [NSRange(location: 4, length: 0)])

        XCTAssertEqual(alpha(inactive, at: 2), 0, accuracy: 0.001)
        XCTAssertEqual(alpha(active, at: 2), 0, accuracy: 0.001)
        XCTAssertEqual(fontKey(inactive, at: 5), fontKey(active, at: 5))

        let tokens = MarkdownAnnotationParser.tokens(in: markdown, selectedRanges: [NSRange(location: 4, length: 0)])
        XCTAssertTrue(tokens.contains { $0.label == "**" && $0.range.location == 2 })
        XCTAssertTrue(tokens.contains { $0.label == "**" && $0.range.location == 8 })
    }

    func testMixedInlineOnlyRevealsFocusedSpan() {
        let markdown = "Mix **bold**, _italic_, `code`, and [link](https://example.com)."
        let ns = markdown as NSString
        let boldTokens = MarkdownAnnotationParser.tokens(in: markdown, selectedRanges: [NSRange(location: ns.range(of: "bold").location, length: 0)])
        XCTAssertEqual(boldTokens.map(\.label), ["**", "**"])

        let linkTokens = MarkdownAnnotationParser.tokens(in: markdown, selectedRanges: [NSRange(location: ns.range(of: "link").location, length: 0)])
        XCTAssertEqual(linkTokens.map(\.label), ["[link](https://example.com)"])
    }

    func testUndoRevertsTextChangeWithoutStyleUndoStep() {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        textView.loadMarkdown("Hello **world**")
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText("!", replacementRange: textView.selectedRange())

        XCTAssertEqual(textView.string, "Hello **world**!")
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Hello **world**")
    }

    func testViewScaleDefaultsCompactAndScalesTypographyAndSpacing() {
        let compact = MarkdownTheme.clean
        let zoomed = compact.zoomedIn()

        XCTAssertEqual(compact.viewScale, MarkdownTheme.defaultViewScale, accuracy: 0.001)
        XCTAssertEqual(zoomed.viewScale, compact.viewScale * MarkdownTheme.zoomStep, accuracy: 0.001)
        XCTAssertLessThan(compact.bodyFont.pointSize, 17)
        XCTAssertGreaterThan(zoomed.bodyFont.pointSize, compact.bodyFont.pointSize)

        let compactParagraph = compact.paragraphStyle()
        let zoomedParagraph = zoomed.paragraphStyle()
        XCTAssertLessThan(compactParagraph.paragraphSpacing, 12)
        XCTAssertGreaterThan(zoomedParagraph.paragraphSpacing, compactParagraph.paragraphSpacing)
    }

    func testViewZoomDoesNotChangeMarkdownSource() {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let markdown = "# Title\n\nA **markdown** document."
        textView.loadMarkdown(markdown)
        textView.increaseTextSize()
        textView.decreaseTextSize()
        textView.resetTextSize()

        XCTAssertEqual(textView.string, markdown)
        XCTAssertEqual(textView.styler.theme.viewScale, MarkdownTheme.defaultViewScale, accuracy: 0.001)
    }

    func testDocumentIORoundTripUsesUTF8Markdown() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sample.md")
        let markdown = "# Saved\n\nA **markdown** file."

        try MarkdownDocumentIO.write(markdown, to: url)
        XCTAssertEqual(try MarkdownDocumentIO.read(from: url), markdown)
    }

    private func alpha(_ attributed: NSAttributedString, at index: Int) -> CGFloat {
        let color = attributed.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
        return color?.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1
    }

    private func fontKey(_ attributed: NSAttributedString, at index: Int) -> String {
        let font = attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        return "\(font?.fontName ?? "nil")-\(font?.pointSize ?? 0)"
    }

    private func colorKey(_ attributed: NSAttributedString, at index: Int) -> String {
        let color = (attributed.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)?.usingColorSpace(.deviceRGB)
        return String(format: "%.3f-%.3f-%.3f-%.3f", color?.redComponent ?? 0, color?.greenComponent ?? 0, color?.blueComponent ?? 0, color?.alphaComponent ?? 0)
    }
}
