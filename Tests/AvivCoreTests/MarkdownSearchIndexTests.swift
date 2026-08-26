import XCTest

@testable import AvivCore

final class MarkdownSearchIndexTests: XCTestCase {
    func testFindsCaseAndDiacriticInsensitiveMatchesWithSourceRanges() {
        let markdown = "Café cafe CAFÉ cafeteria"

        let matches = MarkdownSearchIndex.findMatches(in: markdown, query: "cafe")
        let source = markdown as NSString

        XCTAssertEqual(matches.count, 4)
        XCTAssertEqual(
            matches.map { source.substring(with: $0) },
            ["Café", "cafe", "CAFÉ", "cafe"]
        )
        XCTAssertEqual(matches.map(\.location), matches.map(\.location).sorted())
    }

    func testEmptyQueryHasNoMatches() {
        XCTAssertEqual(MarkdownSearchIndex.findMatches(in: "# Document", query: ""), [])
    }

    func testHighlightsHeadingSectionsAndDirectOutlineRowsContainingMatches() {
        let markdown = """
            # Alpha

            target in the parent section

            ## Clean child

            Nothing here.

            # Beta

            ## Hit child

            target in the child section
            - target list row

            | Area | Result |
            | --- | --- |
            | Search | target table row |
            """ + "\n"
        let index = MarkdownDocumentRenderIndex(markdown: markdown)
        let matches = MarkdownSearchIndex.findMatches(in: markdown, query: "target")

        let highlighted = MarkdownSearchIndex.outlineHitItemIndexes(
            outlineItems: index.outlineItems,
            matchRanges: matches,
            documentLength: index.markdownLength
        )

        XCTAssertEqual(highlighted, IndexSet([0, 2, 3, 4, 5]))
        XCTAssertEqual(index.outlineItems[0].title, "Alpha")
        XCTAssertEqual(index.outlineItems[1].title, "Clean child")
        XCTAssertEqual(index.outlineItems[2].title, "Beta")
        XCTAssertEqual(index.outlineItems[3].title, "Hit child")
        XCTAssertEqual(index.outlineItems[4].kind, .unorderedList(depth: 0))
        XCTAssertEqual(index.outlineItems[5].kind, .table(columns: 2, dataRows: 1))
    }

    func testSearchDoesNotProduceOverlappingMatches() {
        let matches = MarkdownSearchIndex.findMatches(in: "aaaa", query: "aa")

        XCTAssertEqual(
            matches,
            [
                NSRange(location: 0, length: 2),
                NSRange(location: 2, length: 2),
            ]
        )
    }
}
