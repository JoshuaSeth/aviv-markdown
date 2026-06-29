import Foundation

public struct MarkdownTableCell: Equatable {
    public let sourceRange: NSRange
    public let contentRange: NSRange
    public let text: String
}

public struct MarkdownTableRow: Equatable {
    public let lineRange: NSRange
    public let contentRange: NSRange
    public let cells: [MarkdownTableCell]
    public let isHeader: Bool
    public let isSeparator: Bool
}

public struct MarkdownTableBlock: Equatable {
    public let rows: [MarkdownTableRow]

    public var range: NSRange {
        guard let first = rows.first, let last = rows.last else {
            return NSRange(location: 0, length: 0)
        }
        return NSRange(location: first.lineRange.location, length: NSMaxRange(last.lineRange) - first.lineRange.location)
    }
}

public enum MarkdownTableParser {
    public static func blocks(in markdown: String) -> [MarkdownTableBlock] {
        let nsString = markdown as NSString
        guard nsString.length > 0 else { return [] }

        let lines = documentLines(in: nsString)
        var blocks: [MarkdownTableBlock] = []
        var index = 0
        var insideFence = false

        while index < lines.count {
            let line = lines[index]
            let text = nsString.substring(with: line.contentRange)
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            if isFence(trimmed) {
                insideFence.toggle()
                index += 1
                continue
            }

            guard !insideFence else {
                index += 1
                continue
            }

            if index + 1 < lines.count,
               isPotentialTableLine(text),
               isSeparatorLine(nsString.substring(with: lines[index + 1].contentRange)) {
                var rows: [MarkdownTableRow] = []
                rows.append(row(from: line, in: nsString, isHeader: true, isSeparator: false))
                rows.append(row(from: lines[index + 1], in: nsString, isHeader: false, isSeparator: true))
                index += 2

                while index < lines.count {
                    let candidate = nsString.substring(with: lines[index].contentRange)
                    guard isPotentialTableLine(candidate), !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        break
                    }
                    rows.append(row(from: lines[index], in: nsString, isHeader: false, isSeparator: false))
                    index += 1
                }

                if rows.contains(where: { !$0.isSeparator && !$0.cells.isEmpty }) {
                    blocks.append(MarkdownTableBlock(rows: rows))
                }
                continue
            }

            index += 1
        }

        return blocks
    }

    public static func rowMap(in markdown: String) -> [Int: MarkdownTableRow] {
        var map: [Int: MarkdownTableRow] = [:]
        for block in blocks(in: markdown) {
            for row in block.rows {
                map[row.contentRange.location] = row
            }
        }
        return map
    }

    public static func block(containing location: Int, in markdown: String) -> MarkdownTableBlock? {
        blocks(in: markdown).first { NSLocationInRange(location, $0.range) || location == NSMaxRange($0.range) }
    }

    private struct DocumentLine {
        let lineRange: NSRange
        let contentRange: NSRange
    }

    private static func documentLines(in nsString: NSString) -> [DocumentLine] {
        var lines: [DocumentLine] = []
        var index = 0

        while index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            lines.append(DocumentLine(lineRange: lineRange, contentRange: rangeWithoutLineEnding(lineRange, in: nsString)))
            index = NSMaxRange(lineRange)
        }

        if nsString.length == 0 {
            lines.append(DocumentLine(lineRange: NSRange(location: 0, length: 0), contentRange: NSRange(location: 0, length: 0)))
        }

        return lines
    }

    private static func row(from line: DocumentLine, in nsString: NSString, isHeader: Bool, isSeparator: Bool) -> MarkdownTableRow {
        let cells = parseCells(in: nsString, contentRange: line.contentRange)
        return MarkdownTableRow(
            lineRange: line.lineRange,
            contentRange: line.contentRange,
            cells: cells,
            isHeader: isHeader,
            isSeparator: isSeparator
        )
    }

    private static func parseCells(in nsString: NSString, contentRange: NSRange) -> [MarkdownTableCell] {
        guard contentRange.length > 0 else { return [] }

        var segments: [NSRange] = []
        var segmentStart = contentRange.location
        var location = contentRange.location
        let end = NSMaxRange(contentRange)

        while location < end {
            let character = nsString.character(at: location)
            let isEscaped = location > contentRange.location && nsString.character(at: location - 1) == 92
            if character == 124, !isEscaped {
                segments.append(NSRange(location: segmentStart, length: location - segmentStart))
                segmentStart = location + 1
            }
            location += 1
        }
        segments.append(NSRange(location: segmentStart, length: end - segmentStart))

        if let first = segments.first, nsString.substring(with: first).trimmingCharacters(in: .whitespaces).isEmpty, contentRange.length > 0, nsString.character(at: contentRange.location) == 124 {
            segments.removeFirst()
        }
        if let last = segments.last, nsString.substring(with: last).trimmingCharacters(in: .whitespaces).isEmpty, contentRange.length > 0, nsString.character(at: end - 1) == 124 {
            segments.removeLast()
        }

        return segments.map { segment in
            let content = trimmedRange(segment, in: nsString)
            return MarkdownTableCell(
                sourceRange: segment,
                contentRange: content,
                text: nsString.substring(with: content)
            )
        }
    }

    private static func isPotentialTableLine(_ line: String) -> Bool {
        line.contains("|") && line.split(separator: "|", omittingEmptySubsequences: false).count >= 2
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        guard isPotentialTableLine(line) else { return false }
        let parts = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }

        return parts.allSatisfy { part in
            guard part.count >= 3 else { return false }
            let trimmed = part.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }
        }
    }

    private static func isFence(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private static func trimmedRange(_ range: NSRange, in nsString: NSString) -> NSRange {
        var location = range.location
        var end = NSMaxRange(range)

        while location < end {
            let character = nsString.character(at: location)
            if character == 32 || character == 9 {
                location += 1
            } else {
                break
            }
        }

        while end > location {
            let character = nsString.character(at: end - 1)
            if character == 32 || character == 9 {
                end -= 1
            } else {
                break
            }
        }

        return NSRange(location: location, length: end - location)
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
