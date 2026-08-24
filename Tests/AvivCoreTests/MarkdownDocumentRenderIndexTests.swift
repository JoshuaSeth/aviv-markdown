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
}
