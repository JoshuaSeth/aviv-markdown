import Foundation

enum MarkdownSourceLineScanner {
    static func contentRanges(in markdown: String) -> [NSRange] {
        let source = markdown as NSString
        guard source.length > 0 else {
            return [NSRange(location: 0, length: 0)]
        }

        var ranges: [NSRange] = []
        ranges.reserveCapacity(max(1, markdown.utf8.count / 48))
        var location = 0

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(contentRange(for: lineRange, in: source))
            location = NSMaxRange(lineRange)
        }

        if endsWithLineBreak(source) {
            ranges.append(NSRange(location: source.length, length: 0))
        }
        return ranges
    }

    private static func contentRange(for lineRange: NSRange, in source: NSString) -> NSRange {
        var contentLength = lineRange.length
        while contentLength > 0 {
            let character = source.character(at: lineRange.location + contentLength - 1)
            guard character == 10 || character == 13 else { break }
            contentLength -= 1
        }
        return NSRange(location: lineRange.location, length: contentLength)
    }

    private static func endsWithLineBreak(_ source: NSString) -> Bool {
        guard source.length > 0 else { return false }
        let character = source.character(at: source.length - 1)
        return character == 10 || character == 13
    }
}
