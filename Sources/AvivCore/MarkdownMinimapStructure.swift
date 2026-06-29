import Foundation

public struct MarkdownMinimapLine: Equatable {
    public enum Kind: Equatable {
        case blank
        case body
        case heading(level: Int)
        case unorderedList(depth: Int)
        case orderedList(depth: Int)
        case taskList(checked: Bool, depth: Int)
        case quote
        case tableHeader(columns: Int)
        case tableSeparator(columns: Int)
        case tableRow(columns: Int)
        case codeFence
        case code
        case thematicBreak
    }

    public let kind: Kind
    public let quoteDepth: Int
    public let textLength: Int

    public init(kind: Kind, quoteDepth: Int = 0, textLength: Int) {
        self.kind = kind
        self.quoteDepth = quoteDepth
        self.textLength = textLength
    }
}

public enum MarkdownMinimapStructure {
    public static func lines(in markdown: String) -> [MarkdownMinimapLine] {
        let nsString = markdown as NSString
        let documentLines = DocumentLine.lines(in: nsString)
        let tableRows = tableRowsByLocation(in: markdown)
        var insideFence = false
        var result: [MarkdownMinimapLine] = []

        for line in documentLines {
            let rawLine = nsString.substring(with: line.contentRange)
            let quoteStripped = stripQuoteMarkers(from: rawLine)
            let content = quoteStripped.content
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            let textLength = trimmed.count

            if isFence(trimmed) {
                result.append(MarkdownMinimapLine(kind: .codeFence, quoteDepth: quoteStripped.quoteDepth, textLength: textLength))
                insideFence.toggle()
                continue
            }

            if insideFence {
                result.append(MarkdownMinimapLine(kind: .code, quoteDepth: quoteStripped.quoteDepth, textLength: textLength))
                continue
            }

            if trimmed.isEmpty {
                result.append(MarkdownMinimapLine(kind: .blank, quoteDepth: quoteStripped.quoteDepth, textLength: 0))
                continue
            }

            if quoteStripped.quoteDepth == 0, let tableRow = tableRows[line.contentRange.location] {
                result.append(MarkdownMinimapLine(
                    kind: tableKind(for: tableRow),
                    quoteDepth: 0,
                    textLength: textLength
                ))
                continue
            }

            if let level = headingLevel(in: trimmed) {
                result.append(MarkdownMinimapLine(kind: .heading(level: level), quoteDepth: quoteStripped.quoteDepth, textLength: textLength))
                continue
            }

            if let list = listKind(in: content) {
                result.append(MarkdownMinimapLine(kind: list, quoteDepth: quoteStripped.quoteDepth, textLength: textLength))
                continue
            }

            if isThematicBreak(trimmed) {
                result.append(MarkdownMinimapLine(kind: .thematicBreak, quoteDepth: quoteStripped.quoteDepth, textLength: textLength))
                continue
            }

            let kind: MarkdownMinimapLine.Kind = quoteStripped.quoteDepth > 0 ? .quote : .body
            result.append(MarkdownMinimapLine(kind: kind, quoteDepth: quoteStripped.quoteDepth, textLength: textLength))
        }

        return result
    }

    private struct DocumentLine {
        let contentRange: NSRange

        static func lines(in nsString: NSString) -> [DocumentLine] {
            if nsString.length == 0 {
                return [DocumentLine(contentRange: NSRange(location: 0, length: 0))]
            }

            var lines: [DocumentLine] = []
            var index = 0

            while index < nsString.length {
                let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
                lines.append(DocumentLine(contentRange: rangeWithoutLineEnding(lineRange, in: nsString)))
                index = NSMaxRange(lineRange)
            }

            return lines
        }

        private static func rangeWithoutLineEnding(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
            var length = lineRange.length
            while length > 0 {
                let character = nsString.character(at: lineRange.location + length - 1)
                if character == 10 || character == 13 {
                    length -= 1
                } else {
                    break
                }
            }
            return NSRange(location: lineRange.location, length: length)
        }
    }

    private static func tableRowsByLocation(in markdown: String) -> [Int: MarkdownTableRow] {
        var rows: [Int: MarkdownTableRow] = [:]
        for block in MarkdownTableParser.blocks(in: markdown) {
            for row in block.rows {
                rows[row.contentRange.location] = row
            }
        }
        return rows
    }

    private static func tableKind(for row: MarkdownTableRow) -> MarkdownMinimapLine.Kind {
        let columns = max(1, row.cells.count)
        if row.isHeader {
            return .tableHeader(columns: columns)
        }
        if row.isSeparator {
            return .tableSeparator(columns: columns)
        }
        return .tableRow(columns: columns)
    }

    private static func stripQuoteMarkers(from line: String) -> (content: String, quoteDepth: Int) {
        var content = line
        var quoteDepth = 0

        while true {
            let quoteCandidate = content.drop(while: { $0 == " " || $0 == "\t" })
            guard quoteCandidate.first == ">" else { break }
            content = String(quoteCandidate)
            quoteDepth += 1
            content.removeFirst()
            if content.first == " " || content.first == "\t" {
                content.removeFirst()
            }
        }

        return (content, quoteDepth)
    }

    private static func headingLevel(in trimmed: String) -> Int? {
        var level = 0
        for character in trimmed {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }

        guard (1...6).contains(level) else { return nil }
        let index = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard index == trimmed.endIndex || trimmed[index] == " " || trimmed[index] == "\t" else {
            return nil
        }
        return level
    }

    private static func listKind(in content: String) -> MarkdownMinimapLine.Kind? {
        let leadingWhitespace = content.prefix { $0 == " " || $0 == "\t" }
        let depth = min(5, leadingWhitespace.reduce(0) { partial, character in
            partial + (character == "\t" ? 2 : 1)
        } / 2)
        let trimmed = content.trimmingCharacters(in: .whitespaces)

        if let body = unorderedListBody(in: trimmed) {
            if let checked = taskState(in: body) {
                return .taskList(checked: checked, depth: depth)
            }
            return .unorderedList(depth: depth)
        }

        if let body = orderedListBody(in: trimmed) {
            if let checked = taskState(in: body) {
                return .taskList(checked: checked, depth: depth)
            }
            return .orderedList(depth: depth)
        }

        return nil
    }

    private static func unorderedListBody(in trimmed: String) -> Substring? {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "+" else { return nil }
        let afterMarker = trimmed.dropFirst()
        guard afterMarker.first == " " || afterMarker.first == "\t" else { return nil }
        return afterMarker.dropFirst()
    }

    private static func orderedListBody(in trimmed: String) -> Substring? {
        var index = trimmed.startIndex
        var digitCount = 0

        while index < trimmed.endIndex, trimmed[index].isNumber {
            digitCount += 1
            index = trimmed.index(after: index)
        }

        guard digitCount > 0, index < trimmed.endIndex, trimmed[index] == "." || trimmed[index] == ")" else {
            return nil
        }

        let markerEnd = trimmed.index(after: index)
        guard markerEnd < trimmed.endIndex, trimmed[markerEnd] == " " || trimmed[markerEnd] == "\t" else {
            return nil
        }

        return trimmed[trimmed.index(after: markerEnd)...]
    }

    private static func taskState(in body: Substring) -> Bool? {
        let trimmedBody = body.trimmingCharacters(in: .whitespaces)
        guard trimmedBody.count >= 3,
              trimmedBody.first == "[",
              trimmedBody[trimmedBody.index(trimmedBody.startIndex, offsetBy: 2)] == "]" else {
            return nil
        }

        let marker = trimmedBody[trimmedBody.index(after: trimmedBody.startIndex)]
        if marker == "x" || marker == "X" {
            return true
        }
        if marker == " " {
            return false
        }
        return nil
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let first = compact.first, first == "-" || first == "_" || first == "*" else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func isFence(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }
}
