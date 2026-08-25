import Foundation

public struct MarkdownDocumentRenderIndex {
    public let markdownLength: Int
    public let tableBlocks: [MarkdownTableBlock]
    public let tableRowsByLocation: [Int: MarkdownTableRow]
    public let minimapLines: [MarkdownMinimapLine]
    public let sourceLineRanges: [NSRange]
    public let outlineItems: [MarkdownDocumentOutlineItem]
    public let totalOutlineItemCount: Int
    public let omittedOutlineItemCount: Int

    public init(markdown: String) {
        let blocks = MarkdownTableParser.blocks(in: markdown)
        var tableRows: [Int: MarkdownTableRow] = [:]
        for block in blocks {
            for row in block.rows {
                tableRows[row.contentRange.location] = row
            }
        }

        let lineRanges = MarkdownSourceLineScanner.contentRanges(in: markdown)
        let lines = MarkdownMinimapStructure.lines(
            in: markdown,
            sourceLineRanges: lineRanges,
            tableRowsByLocation: tableRows
        )
        let outline = MarkdownDocumentOutline.build(
            markdown: markdown,
            sourceLineRanges: lineRanges,
            minimapLines: lines,
            tableBlocks: blocks
        )

        markdownLength = (markdown as NSString).length
        tableBlocks = blocks
        tableRowsByLocation = tableRows
        minimapLines = lines
        sourceLineRanges = lineRanges
        outlineItems = outline.items
        totalOutlineItemCount = outline.totalItemCount
        omittedOutlineItemCount = outline.omittedItemCount
    }

    public func tableBlocks(intersecting range: NSRange) -> [MarkdownTableBlock] {
        guard range.location != NSNotFound else { return [] }
        return tableBlocks.filter { block in
            NSIntersectionRange(block.range, range).length > 0
                || range.length == 0 && NSLocationInRange(range.location, block.range)
        }
    }

}
