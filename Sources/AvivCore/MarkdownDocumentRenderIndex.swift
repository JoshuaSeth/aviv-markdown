import Foundation

public struct MarkdownDocumentRenderIndex {
    public let markdownLength: Int
    public let tableBlocks: [MarkdownTableBlock]
    public let tableRowsByLocation: [Int: MarkdownTableRow]
    public let minimapLines: [MarkdownMinimapLine]
    public let sourceLineRanges: [NSRange]

    public init(markdown: String) {
        let blocks = MarkdownTableParser.blocks(in: markdown)
        var tableRows: [Int: MarkdownTableRow] = [:]
        for block in blocks {
            for row in block.rows {
                tableRows[row.contentRange.location] = row
            }
        }

        markdownLength = (markdown as NSString).length
        tableBlocks = blocks
        tableRowsByLocation = tableRows
        minimapLines = MarkdownMinimapStructure.lines(
            in: markdown,
            tableRowsByLocation: tableRows
        )
        sourceLineRanges = Self.lineRanges(in: markdown)
    }

    public func tableBlocks(intersecting range: NSRange) -> [MarkdownTableBlock] {
        guard range.location != NSNotFound else { return [] }
        return tableBlocks.filter { block in
            NSIntersectionRange(block.range, range).length > 0
                || range.length == 0 && NSLocationInRange(range.location, block.range)
        }
    }

    private static func lineRanges(in markdown: String) -> [NSRange] {
        let nsString = markdown as NSString
        guard nsString.length > 0 else { return [NSRange(location: 0, length: 0)] }

        var ranges: [NSRange] = []
        var index = 0
        while index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            var contentLength = lineRange.length
            while contentLength > 0 {
                let character = nsString.character(at: lineRange.location + contentLength - 1)
                guard character == 10 || character == 13 else { break }
                contentLength -= 1
            }
            ranges.append(NSRange(location: lineRange.location, length: contentLength))
            index = NSMaxRange(lineRange)
        }

        if markdown.hasSuffix("\n") || markdown.hasSuffix("\r") {
            ranges.append(NSRange(location: nsString.length, length: 0))
        }
        return ranges
    }
}
