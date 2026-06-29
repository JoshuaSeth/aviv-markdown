import Foundation

public struct MarkdownEditableSourceSpan: Equatable {
    public enum Kind: Equatable {
        case image
        case link
    }

    public let range: NSRange
    public let source: String
    public let kind: Kind
}

public enum MarkdownSourceSpanParser {
    public static func editableSpan(containing location: Int, in markdown: String) -> MarkdownEditableSourceSpan? {
        imageSpan(containing: location, in: markdown) ?? linkSpan(containing: location, in: markdown)
    }

    public static func imageSpan(containing location: Int, in markdown: String) -> MarkdownEditableSourceSpan? {
        sourceSpan(containing: location, in: markdown, pattern: MarkdownPatterns.image, kind: .image)
    }

    public static func linkSpan(containing location: Int, in markdown: String) -> MarkdownEditableSourceSpan? {
        sourceSpan(containing: location, in: markdown, pattern: MarkdownPatterns.link, kind: .link)
    }

    private static func sourceSpan(
        containing location: Int,
        in markdown: String,
        pattern: String,
        kind: MarkdownEditableSourceSpan.Kind
    ) -> MarkdownEditableSourceSpan? {
        let nsString = markdown as NSString
        guard nsString.length > 0 else { return nil }

        let safeLocation = min(max(0, location), nsString.length - 1)
        let lineRange = nsString.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = nsString.substring(with: lineRange)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        for match in matches {
            let globalRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            if NSLocationInRange(location, globalRange) || location == NSMaxRange(globalRange) {
                return MarkdownEditableSourceSpan(
                    range: globalRange,
                    source: nsString.substring(with: globalRange),
                    kind: kind
                )
            }
        }

        return nil
    }
}
