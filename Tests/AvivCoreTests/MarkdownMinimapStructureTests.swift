import XCTest
@testable import AvivCore

final class MarkdownMinimapStructureTests: XCTestCase {
    func testClassifiesDocumentStructureForMinimap() {
        let markdown = """
        # Heading
        Body text
        - Bullet
          1. Ordered
        - [x] Done
        > - [ ] Quoted task
        | A | B |
        | --- | --- |
        | 1 | 2 |
        ---
        ```swift
        let value = 1
        ```
        """

        let lines = MarkdownMinimapStructure.lines(in: markdown)

        XCTAssertEqual(lines[0].kind, .heading(level: 1))
        XCTAssertEqual(lines[1].kind, .body)
        XCTAssertEqual(lines[2].kind, .unorderedList(depth: 0))
        XCTAssertEqual(lines[3].kind, .orderedList(depth: 1))
        XCTAssertEqual(lines[4].kind, .taskList(checked: true, depth: 0))
        XCTAssertEqual(lines[5].kind, .taskList(checked: false, depth: 0))
        XCTAssertEqual(lines[5].quoteDepth, 1)
        XCTAssertEqual(lines[6].kind, .tableHeader(columns: 2))
        XCTAssertEqual(lines[7].kind, .tableSeparator(columns: 2))
        XCTAssertEqual(lines[8].kind, .tableRow(columns: 2))
        XCTAssertEqual(lines[9].kind, .thematicBreak)
        XCTAssertEqual(lines[10].kind, .codeFence)
        XCTAssertEqual(lines[11].kind, .code)
        XCTAssertEqual(lines[12].kind, .codeFence)
    }

    func testPipesInsideCodeFenceDoNotBecomeTables() {
        let markdown = """
        ```text
        | Not | Table |
        | --- | ----- |
        ```
        """

        let lines = MarkdownMinimapStructure.lines(in: markdown)

        XCTAssertEqual(lines.map(\.kind), [.codeFence, .code, .code, .codeFence])
    }
}
