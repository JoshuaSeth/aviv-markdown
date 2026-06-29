import AppKit
import XCTest
@testable import AvivCore

final class MarkdownEdgeCaseTests: XCTestCase {
    private struct EdgeCase {
        let name: String
        let markdown: String
        let cursorNeedle: String
        let expectedAnnotations: [String]
        let expectedTableBlocks: Int

        init(
            _ name: String,
            _ markdown: String,
            cursorNeedle: String? = nil,
            expectedAnnotations: [String] = [],
            expectedTableBlocks: Int = 0
        ) {
            self.name = name
            self.markdown = markdown
            self.cursorNeedle = cursorNeedle ?? markdown
            self.expectedAnnotations = expectedAnnotations
            self.expectedTableBlocks = expectedTableBlocks
        }
    }

    func testFortyManualMarkdownEdgeCasesStayStable() {
        XCTAssertEqual(Self.edgeCases.count, 40)

        for edgeCase in Self.edgeCases {
            let selection = selectionRange(for: edgeCase.cursorNeedle, in: edgeCase.markdown, file: #filePath, line: #line)
            let attributed = MarkdownStyler().attributedString(for: edgeCase.markdown, selectedRanges: [selection])
            XCTAssertEqual(attributed.string, edgeCase.markdown, edgeCase.name)
            XCTAssertEqual(attributed.length, (edgeCase.markdown as NSString).length, edgeCase.name)

            let tables = MarkdownTableParser.blocks(in: edgeCase.markdown)
            XCTAssertEqual(tables.count, edgeCase.expectedTableBlocks, edgeCase.name)
            assertTableVisibilityContract(for: edgeCase, tables: tables, selection: selection)

            let labels = MarkdownAnnotationParser.tokens(in: edgeCase.markdown, selectedRanges: [selection]).map(\.label)
            XCTAssertEqual(labels, edgeCase.expectedAnnotations, edgeCase.name)
        }
    }

    func testInactiveTablesRenderByHidingSourceTextForOverlay() {
        let markdown = """
        | Name | Value |
        | ---- | ----- |
        | Alpha | Beta |
        """
        let attributed = MarkdownStyler().attributedString(for: markdown, selectedRanges: [NSRange(location: (markdown as NSString).length, length: 0)])
        let pipe = (markdown as NSString).range(of: "|").location
        let alpha = (attributed.attribute(.foregroundColor, at: pipe, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.deviceRGB)?
            .alphaComponent
        XCTAssertEqual(alpha ?? 1, 0, accuracy: 0.001)

        let blocks = MarkdownTableParser.blocks(in: markdown)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].rows.filter { !$0.isSeparator }.count, 2)
        XCTAssertEqual(blocks[0].rows[0].cells.map(\.text), ["Name", "Value"])
        XCTAssertEqual(blocks[0].rows[2].cells.map(\.text), ["Alpha", "Beta"])
    }

    func testActiveTableRowKeepsSourceVisibleForEditing() {
        let markdown = """
        | Name | Value |
        | ---- | ----- |
        | Alpha | Beta |
        """
        let cursor = (markdown as NSString).range(of: "Alpha").location
        let attributed = MarkdownStyler().attributedString(for: markdown, selectedRanges: [NSRange(location: cursor, length: 0)])
        let activePipe = (markdown as NSString).range(of: "| Alpha").location
        let alpha = (attributed.attribute(.foregroundColor, at: activePipe, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.deviceRGB)?
            .alphaComponent
        XCTAssertGreaterThan(alpha ?? 0, 0.9)
    }

    func testLinkExpansionIsSingleFullSourceAnnotation() {
        let markdown = "A **bold** _italic_ [link text](https://example.com/a-b) and `code`."
        let cursor = selectionRange(for: "link text", in: markdown, file: #filePath, line: #line)
        let tokens = MarkdownAnnotationParser.tokens(in: markdown, selectedRanges: [cursor])
        XCTAssertTrue(tokens.contains(MarkdownAnnotationToken(
            range: (markdown as NSString).range(of: "[link text](https://example.com/a-b)"),
            label: "[link text](https://example.com/a-b)",
            role: .linkSource
        )))
        XCTAssertFalse(tokens.contains { $0.label == "](https://example.com/a-b)" })
    }

    func testEditableLinkSourceSpanTargetsWholeMarkdownLink() {
        let markdown = "Open [the docs](https://example.com/a_(b)) today."
        let ns = markdown as NSString
        let cursor = ns.range(of: "docs").location
        let span = MarkdownSourceSpanParser.editableSpan(containing: cursor, in: markdown)

        XCTAssertEqual(span?.source, "[the docs](https://example.com/a_(b))")
        XCTAssertEqual(span?.range, ns.range(of: "[the docs](https://example.com/a_(b))"))
        XCTAssertEqual(span?.kind, .link)
    }

    func testEditableImageSourceSpanTargetsWholeMarkdownImage() {
        let markdown = "Look ![diagram](Images/flow.png) here and [not image](https://example.com)."
        let ns = markdown as NSString
        let cursor = ns.range(of: "diagram").location
        let span = MarkdownSourceSpanParser.editableSpan(containing: cursor, in: markdown)

        XCTAssertEqual(span?.source, "![diagram](Images/flow.png)")
        XCTAssertEqual(span?.range, ns.range(of: "![diagram](Images/flow.png)"))
        XCTAssertEqual(span?.kind, .image)
        XCTAssertNil(MarkdownSourceSpanParser.linkSpan(containing: cursor, in: markdown))
    }

    func testFencedPipesAreNotTables() {
        let markdown = """
        ```markdown
        | Not | A table |
        | --- | ------- |
        ```
        """
        XCTAssertTrue(MarkdownTableParser.blocks(in: markdown).isEmpty)
    }

    func testHorizontalRuleRemainsVisible() {
        let markdown = "---"
        let attributed = MarkdownStyler().attributedString(for: markdown, selectedRanges: [NSRange(location: 0, length: 0)])
        let alpha = (attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.deviceRGB)?
            .alphaComponent
        XCTAssertGreaterThan(alpha ?? 0, 0.9)
    }

    private func selectionRange(for needle: String, in markdown: String, file: StaticString, line: UInt) -> NSRange {
        let ns = markdown as NSString
        let range = ns.range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing needle \(needle)", file: file, line: line)
        return NSRange(location: range.location, length: 0)
    }

    private func assertTableVisibilityContract(for edgeCase: EdgeCase, tables: [MarkdownTableBlock], selection: NSRange) {
        let styler = MarkdownStyler()
        if edgeCase.expectedTableBlocks > 0 {
            guard let firstCell = tables.first?.rows.first(where: { !$0.isSeparator })?.cells.first else {
                XCTFail("\(edgeCase.name) missing table cell")
                return
            }

            let inactive = styler.attributedString(
                for: edgeCase.markdown,
                selectedRanges: [NSRange(location: (edgeCase.markdown as NSString).length, length: 0)]
            )
            XCTAssertEqual(alpha(inactive, at: firstCell.contentRange.location), 0, accuracy: 0.001, edgeCase.name)

            let active = styler.attributedString(for: edgeCase.markdown, selectedRanges: [selection])
            let selectedLine = (edgeCase.markdown as NSString).lineRange(for: selection)
            if NSIntersectionRange(selectedLine, firstCell.contentRange).length > 0 {
                XCTAssertGreaterThan(alpha(active, at: firstCell.contentRange.location), 0.9, edgeCase.name)
            }
        } else if edgeCase.markdown.contains("|") {
            let pipe = (edgeCase.markdown as NSString).range(of: "|").location
            if pipe != NSNotFound {
                let attributed = styler.attributedString(for: edgeCase.markdown, selectedRanges: [selection])
                XCTAssertGreaterThan(alpha(attributed, at: pipe), 0.9, edgeCase.name)
            }
        }
    }

    private func alpha(_ attributed: NSAttributedString, at index: Int) -> CGFloat {
        guard index >= 0, index < attributed.length else { return 0 }
        let color = attributed.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
        return color?.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1
    }

    private static let edgeCases: [EdgeCase] = [
        EdgeCase("h1", "# Title", cursorNeedle: "Title", expectedAnnotations: ["#"]),
        EdgeCase("h6", "###### Tiny", cursorNeedle: "Tiny", expectedAnnotations: ["######"]),
        EdgeCase("heading bold", "## A **bold** title", cursorNeedle: "bold", expectedAnnotations: ["##", "**", "**"]),
        EdgeCase("paragraph bold", "This is **bold** text.", cursorNeedle: "bold", expectedAnnotations: ["**", "**"]),
        EdgeCase("underscore italic", "This is _italic_ text.", cursorNeedle: "italic", expectedAnnotations: ["_", "_"]),
        EdgeCase("star italic", "This is *italic* text.", cursorNeedle: "italic", expectedAnnotations: ["*", "*"]),
        EdgeCase("strike", "This is ~~gone~~ text.", cursorNeedle: "gone", expectedAnnotations: ["~~", "~~"]),
        EdgeCase("inline code", "Use `let value = 1` now.", cursorNeedle: "value", expectedAnnotations: ["`", "`"]),
        EdgeCase("code shields markdown", "Use `**not bold**` here.", cursorNeedle: "not bold", expectedAnnotations: ["`", "`"]),
        EdgeCase("basic link", "Read [docs](https://example.com).", cursorNeedle: "docs", expectedAnnotations: ["[docs](https://example.com)"]),
        EdgeCase("long link", "Read [long label](https://example.com/with/a/long/path?x=1).", cursorNeedle: "long label", expectedAnnotations: ["[long label](https://example.com/with/a/long/path?x=1)"]),
        EdgeCase("image syntax", "![Alt text](image.png)", cursorNeedle: "Alt text", expectedAnnotations: ["![Alt text](image.png)"]),
        EdgeCase("mixed inline", "Mix **bold**, _italic_, `code`, and [link](https://example.com).", cursorNeedle: "link", expectedAnnotations: ["[link](https://example.com)"]),
        EdgeCase("two links", "[one](https://one.example) and [two](https://two.example)", cursorNeedle: "two", expectedAnnotations: ["[two](https://two.example)"]),
        EdgeCase("checked task", "- [x] Done with **bold**", cursorNeedle: "bold", expectedAnnotations: ["**", "**"]),
        EdgeCase("unchecked task link", "- [ ] Read [docs](https://example.com)", cursorNeedle: "docs", expectedAnnotations: ["[docs](https://example.com)"]),
        EdgeCase("bullet list", "- Item with _emphasis_", cursorNeedle: "emphasis", expectedAnnotations: ["_", "_"]),
        EdgeCase("ordered list", "1. Item with `code`", cursorNeedle: "code", expectedAnnotations: ["`", "`"]),
        EdgeCase("nested list", "  - Nested **item**", cursorNeedle: "item", expectedAnnotations: ["**", "**"]),
        EdgeCase("blockquote", "> Quote with [link](https://example.com)", cursorNeedle: "link", expectedAnnotations: ["[link](https://example.com)"]),
        EdgeCase("horizontal rule", "---", cursorNeedle: "---"),
        EdgeCase("fenced swift", "```swift\nlet x = 1\n```", cursorNeedle: "swift", expectedAnnotations: ["```swift"]),
        EdgeCase("basic table", "| A | B |\n| --- | --- |\n| 1 | 2 |", cursorNeedle: "1", expectedTableBlocks: 1),
        EdgeCase("aligned table", "| Left | Right |\n| :--- | ---: |\n| a | b |", cursorNeedle: "Left", expectedTableBlocks: 1),
        EdgeCase("table no outer pipes", "A | B\n--- | ---\n1 | 2", cursorNeedle: "2", expectedTableBlocks: 1),
        EdgeCase("table inline code", "| Code | Meaning |\n| --- | --- |\n| `x` | value |", cursorNeedle: "value", expectedTableBlocks: 1),
        EdgeCase("table link", "| Link | URL |\n| --- | --- |\n| [site](https://example.com) | ok |", cursorNeedle: "site", expectedAnnotations: ["[site](https://example.com)"], expectedTableBlocks: 1),
        EdgeCase("table escaped pipe", "| Pattern | Meaning |\n| --- | --- |\n| a\\|b | escaped |", cursorNeedle: "escaped", expectedTableBlocks: 1),
        EdgeCase("false table prose", "A sentence with A | B in it.", cursorNeedle: "sentence"),
        EdgeCase("false table separator missing", "| A | B |\n| no | separator |", cursorNeedle: "no"),
        EdgeCase("fenced table false positive", "```\n| A | B |\n| --- | --- |\n```", cursorNeedle: "A"),
        EdgeCase("url with parens", "See [call](https://example.com/a_(b)).", cursorNeedle: "call", expectedAnnotations: ["[call](https://example.com/a_(b))"]),
        EdgeCase("underscore in word", "snake_case should stay plain.", cursorNeedle: "snake_case"),
        EdgeCase("empty line around bold", "\n**bold**\n", cursorNeedle: "bold", expectedAnnotations: ["**", "**"]),
        EdgeCase("quote task", "> - [ ] Task inside quote", cursorNeedle: "Task"),
        EdgeCase("number dot", "12. Ordered item", cursorNeedle: "Ordered"),
        EdgeCase("number paren", "3) Ordered item", cursorNeedle: "Ordered"),
        EdgeCase("html passthrough", "<span>inline html</span>", cursorNeedle: "inline"),
        EdgeCase("unicode text", "Café **naïve** résumé", cursorNeedle: "naïve", expectedAnnotations: ["**", "**"]),
        EdgeCase("final mixed stress", "### Mix [a](https://a.example) **b** _c_ `d` ~~e~~", cursorNeedle: "Mix", expectedAnnotations: ["###"])
    ]
}
