import Foundation

public struct MarkdownDocumentOutlineItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case table(columns: Int, dataRows: Int)
        case unorderedList(depth: Int)
        case orderedList(depth: Int)
        case taskList(checked: Bool, depth: Int)
    }

    public let kind: Kind
    public let title: String
    public let sourceRange: NSRange
    public let lineNumber: Int

    public init(kind: Kind, title: String, sourceRange: NSRange, lineNumber: Int) {
        self.kind = kind
        self.title = title
        self.sourceRange = sourceRange
        self.lineNumber = lineNumber
    }
}

struct MarkdownDocumentOutline {
    static let maximumExposedItems = 200

    let items: [MarkdownDocumentOutlineItem]
    let totalItemCount: Int

    var omittedItemCount: Int {
        max(0, totalItemCount - items.count)
    }

    static func build(
        markdown: String,
        sourceLineRanges: [NSRange],
        minimapLines: [MarkdownMinimapLine],
        tableBlocks: [MarkdownTableBlock]
    ) -> MarkdownDocumentOutline {
        precondition(
            sourceLineRanges.count == minimapLines.count,
            "The shared source-line index must agree with minimap metadata."
        )

        let source = markdown as NSString
        let tableByHeaderLocation = Dictionary(
            uniqueKeysWithValues: tableBlocks.compactMap { block in
                block.rows.first.map { ($0.contentRange.location, block) }
            }
        )
        var items: [MarkdownDocumentOutlineItem] = []
        items.reserveCapacity(min(Self.maximumExposedItems, sourceLineRanges.count))
        var totalItemCount = 0

        for (index, pair) in zip(sourceLineRanges, minimapLines).enumerated() {
            let sourceRange = pair.0
            let line = pair.1
            guard line.kind.contributesToDocumentOutline else { continue }
            totalItemCount += 1
            guard items.count < Self.maximumExposedItems else { continue }
            let item: MarkdownDocumentOutlineItem?

            switch line.kind {
            case .heading(let level):
                item = MarkdownDocumentOutlineItem(
                    kind: .heading(level: level),
                    title: headingTitle(source.substring(with: sourceRange), level: level),
                    sourceRange: sourceRange,
                    lineNumber: index + 1
                )
            case .tableHeader(let columns):
                guard let block = tableByHeaderLocation[sourceRange.location] else {
                    item = nil
                    break
                }
                let header = block.rows.first?.cells.map(\.text).filter { !$0.isEmpty } ?? []
                let dataRows = block.rows.filter { !$0.isHeader && !$0.isSeparator }.count
                item = MarkdownDocumentOutlineItem(
                    kind: .table(columns: columns, dataRows: dataRows),
                    title: header.isEmpty ? "Table" : "Table: \(header.joined(separator: ", "))",
                    sourceRange: block.range,
                    lineNumber: index + 1
                )
            case .unorderedList(let depth):
                item = listItem(
                    kind: .unorderedList(depth: depth),
                    source: source.substring(with: sourceRange),
                    sourceRange: sourceRange,
                    lineNumber: index + 1
                )
            case .orderedList(let depth):
                item = listItem(
                    kind: .orderedList(depth: depth),
                    source: source.substring(with: sourceRange),
                    sourceRange: sourceRange,
                    lineNumber: index + 1
                )
            case .taskList(let checked, let depth):
                item = listItem(
                    kind: .taskList(checked: checked, depth: depth),
                    source: source.substring(with: sourceRange),
                    sourceRange: sourceRange,
                    lineNumber: index + 1
                )
            default:
                item = nil
            }

            guard let item else { continue }
            items.append(item)
        }

        return MarkdownDocumentOutline(items: items, totalItemCount: totalItemCount)
    }

    private static func headingTitle(_ source: String, level: Int) -> String {
        let quoteStripped = strippingQuoteMarkers(source)
            .trimmingCharacters(in: .whitespaces)
        let body = quoteStripped.dropFirst(min(level, quoteStripped.count))
            .trimmingCharacters(in: .whitespaces)
        let trimmed = body.replacingOccurrences(
            of: #"\s+#+\s*$"#,
            with: "",
            options: .regularExpression
        )
        return summarized(trimmed, defaultValue: "Untitled heading")
    }

    private static func listItem(
        kind: MarkdownDocumentOutlineItem.Kind,
        source: String,
        sourceRange: NSRange,
        lineNumber: Int
    ) -> MarkdownDocumentOutlineItem {
        let quoteStripped = strippingQuoteMarkers(source)
        let body = quoteStripped.replacingOccurrences(
            of: #"^\s*(?:[-+*]|\d+[.)])\s+(?:\[[ xX]\]\s*)?"#,
            with: "",
            options: .regularExpression
        )
        return MarkdownDocumentOutlineItem(
            kind: kind,
            title: summarized(body, defaultValue: "Empty list item"),
            sourceRange: sourceRange,
            lineNumber: lineNumber
        )
    }

    private static func strippingQuoteMarkers(_ source: String) -> String {
        source.replacingOccurrences(
            of: #"^\s*(?:>\s*)+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func summarized(_ text: String, defaultValue: String) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !compact.isEmpty else { return defaultValue }
        let maximumCharacters = 96
        guard compact.count > maximumCharacters else { return compact }
        let end = compact.index(compact.startIndex, offsetBy: maximumCharacters - 1)
        return String(compact[..<end]) + "…"
    }
}

extension MarkdownMinimapLine.Kind {
    fileprivate var contributesToDocumentOutline: Bool {
        switch self {
        case .heading, .tableHeader, .unorderedList, .orderedList, .taskList:
            return true
        default:
            return false
        }
    }
}
