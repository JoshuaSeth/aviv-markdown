import XCTest

@testable import AvivCore

final class MarkdownDocumentRenderIndexTests: XCTestCase {
    func testBuildsSharedTableAndMinimapMetadataFromOneDocumentSnapshot() throws {
        let markdown = """
            # Indexed document

            | Name | Value |
            | --- | --- |
            | Alpha | 1 |
            | Beta | 2 |

            Searchable source remains native text.
            """

        let index = MarkdownDocumentRenderIndex(markdown: markdown)
        let block = try XCTUnwrap(index.tableBlocks.first)

        XCTAssertEqual(index.markdownLength, (markdown as NSString).length)
        XCTAssertEqual(index.tableBlocks.count, 1)
        XCTAssertEqual(block.rows.count, 4)
        XCTAssertEqual(index.tableRowsByLocation.count, 4)
        XCTAssertEqual(index.minimapLines.count, index.sourceLineRanges.count)
        XCTAssertEqual(index.minimapLines[2].kind, .tableHeader(columns: 2))
        XCTAssertEqual(index.minimapLines[3].kind, .tableSeparator(columns: 2))
        XCTAssertEqual(index.minimapLines[4].kind, .tableRow(columns: 2))
        XCTAssertEqual(index.tableBlocks(intersecting: block.rows[2].contentRange), [block])
    }

    func testIntersectionLookupDoesNotReturnDistantTables() throws {
        let markdown = """
            | A | B |
            | --- | --- |
            | 1 | 2 |

            Middle text.

            | C | D |
            | --- | --- |
            | 3 | 4 |
            """
        let index = MarkdownDocumentRenderIndex(markdown: markdown)
        XCTAssertEqual(index.tableBlocks.count, 2)
        let second = try XCTUnwrap(index.tableBlocks.last)

        XCTAssertEqual(index.tableBlocks(intersecting: second.rows[2].contentRange), [second])
    }

    func testMinimapAndSourceRangesAlwaysAgreeIncludingTerminalNewlines() {
        let fixtures = [
            "",
            "# Heading",
            "# Heading\n",
            "# Heading\r",
            "# Heading\r\n",
            "# Heading\n\n- List\n",
            "| A | B |\r\n| --- | --- |\r\n| 1 | 2 |\r\n",
        ]

        for markdown in fixtures {
            let index = MarkdownDocumentRenderIndex(markdown: markdown)
            XCTAssertEqual(
                index.minimapLines.count,
                index.sourceLineRanges.count,
                "fixture: \(markdown.debugDescription)"
            )
        }
    }

    func testBuildsBoundedActionableOutlineForHeadingsTablesAndLists() throws {
        let markdown = """
            # Release plan

            - Ship the editor
            1. Verify the download
            - [x] Preserve source

            | Area | Status |
            | --- | --- |
            | Sidebar | Reliable |
            """ + "\n"

        let index = MarkdownDocumentRenderIndex(markdown: markdown)

        XCTAssertEqual(index.minimapLines.count, index.sourceLineRanges.count)
        XCTAssertEqual(index.totalOutlineItemCount, 5)
        XCTAssertEqual(index.omittedOutlineItemCount, 0)
        XCTAssertEqual(index.outlineItems.count, 5)
        XCTAssertEqual(index.outlineItems[0].kind, .heading(level: 1))
        XCTAssertEqual(index.outlineItems[0].title, "Release plan")
        XCTAssertEqual(index.outlineItems[0].lineNumber, 1)
        XCTAssertEqual(index.outlineItems[1].kind, .unorderedList(depth: 0))
        XCTAssertEqual(index.outlineItems[2].kind, .orderedList(depth: 0))
        XCTAssertEqual(index.outlineItems[3].kind, .taskList(checked: true, depth: 0))
        XCTAssertEqual(index.outlineItems[4].kind, .table(columns: 2, dataRows: 1))
        XCTAssertEqual(index.outlineItems[4].title, "Table: Area, Status")
    }

    func testAccessibilityOutlineIsCappedForVeryLargeListDocuments() {
        let markdown = (0..<1_000).map { "- Outline item \($0)" }.joined(separator: "\n") + "\n"

        let index = MarkdownDocumentRenderIndex(markdown: markdown)

        XCTAssertEqual(index.totalOutlineItemCount, 1_000)
        XCTAssertEqual(index.outlineItems.count, 200)
        XCTAssertEqual(index.omittedOutlineItemCount, 800)
        XCTAssertEqual(index.minimapLines.count, index.sourceLineRanges.count)
    }
}
