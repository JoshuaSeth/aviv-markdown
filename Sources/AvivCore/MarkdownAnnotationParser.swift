import Foundation

public struct MarkdownAnnotationToken: Equatable {
    public enum Role: Equatable {
        case heading
        case inlineDelimiter
        case linkSource
        case linkTarget
        case codeFence
    }

    public let range: NSRange
    public let label: String
    public let role: Role

    public init(range: NSRange, label: String, role: Role) {
        self.range = range
        self.label = label
        self.role = role
    }
}

public enum MarkdownAnnotationParser {
    public static func tokens(in markdown: String, selectedRanges: [NSRange]) -> [MarkdownAnnotationToken] {
        let nsString = markdown as NSString
        guard nsString.length > 0 else { return [] }

        var output: [MarkdownAnnotationToken] = []
        var visitedLineStarts = Set<Int>()

        for selection in selectedRanges {
            let targetRange = selection.length == 0 ? NSRange(location: min(selection.location, max(0, nsString.length - 1)), length: 0) : selection
            let lineRange = nsString.lineRange(for: targetRange)
            guard !visitedLineStarts.contains(lineRange.location) else { continue }
            visitedLineStarts.insert(lineRange.location)
            let contentRange = rangeWithoutLineEnding(lineRange, in: nsString)
            let line = nsString.substring(with: contentRange)
            let focusedRanges = selectedRanges.compactMap { selection -> NSRange? in
                let intersection = selection.length == 0
                    ? NSRange(location: min(selection.location, max(0, nsString.length - 1)), length: 0)
                    : NSIntersectionRange(selection, contentRange)
                guard intersection.location != NSNotFound else { return nil }
                return NSRange(location: max(0, intersection.location - contentRange.location), length: intersection.length)
            }
            output.append(contentsOf: tokens(inLine: line, contentRange: contentRange, focusedRanges: focusedRanges))
        }

        return output
    }

    private static func tokens(inLine line: String, contentRange: NSRange, focusedRanges: [NSRange]) -> [MarkdownAnnotationToken] {
        var tokens: [MarkdownAnnotationToken] = []
        let nsLine = line as NSString
        let fullLocalRange = NSRange(location: 0, length: nsLine.length)

        if let heading = firstMatch(pattern: #"^(#{1,6})\s+"#, in: line) {
            let markerRange = heading.range(at: 1)
            let global = NSRange(location: contentRange.location + markerRange.location, length: markerRange.length)
            tokens.append(MarkdownAnnotationToken(range: global, label: nsLine.substring(with: markerRange), role: .heading))
        }

        if let fence = firstMatch(pattern: #"^\s*(```|~~~).*$"#, in: line) {
            tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + fence.range.location, length: fence.range.length), label: nsLine.substring(with: fence.range), role: .codeFence))
        }

        var protectedRanges: [NSRange] = []

        collect(pattern: "`([^`\\n]+)`", in: line, range: fullLocalRange, protectedRanges: protectedRanges) { match in
            if shouldReveal(match.range, focusedRanges: focusedRanges) {
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + match.range.location, length: 1), label: "`", role: .inlineDelimiter))
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + NSMaxRange(match.range) - 1, length: 1), label: "`", role: .inlineDelimiter))
            }
            protectedRanges.append(match.range)
        }

        collect(pattern: MarkdownPatterns.image, in: line, range: fullLocalRange, protectedRanges: protectedRanges) { match in
            if shouldReveal(match.range, focusedRanges: focusedRanges) {
                tokens.append(MarkdownAnnotationToken(
                    range: NSRange(location: contentRange.location + match.range.location, length: match.range.length),
                    label: nsLine.substring(with: match.range),
                    role: .linkSource
                ))
            }
            protectedRanges.append(match.range)
        }

        collect(pattern: MarkdownPatterns.link, in: line, range: fullLocalRange, protectedRanges: protectedRanges) { match in
            if shouldReveal(match.range, focusedRanges: focusedRanges) {
                tokens.append(MarkdownAnnotationToken(
                    range: NSRange(location: contentRange.location + match.range.location, length: match.range.length),
                    label: nsLine.substring(with: match.range),
                    role: .linkSource
                ))
            }
            protectedRanges.append(match.range)
        }

        collect(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1", in: line, range: fullLocalRange, protectedRanges: protectedRanges) { match in
            let delimiter = match.range(at: 1)
            let content = match.range(at: 2)
            let label = nsLine.substring(with: delimiter)
            if shouldReveal(match.range, focusedRanges: focusedRanges) {
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + delimiter.location, length: delimiter.length), label: label, role: .inlineDelimiter))
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + NSMaxRange(content), length: delimiter.length), label: label, role: .inlineDelimiter))
            }
            protectedRanges.append(match.range)
        }

        collect(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)~~", in: line, range: fullLocalRange, protectedRanges: protectedRanges) { match in
            let delimiter = match.range(at: 1)
            let content = match.range(at: 2)
            if shouldReveal(match.range, focusedRanges: focusedRanges) {
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + delimiter.location, length: delimiter.length), label: "~~", role: .inlineDelimiter))
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + NSMaxRange(content), length: delimiter.length), label: "~~", role: .inlineDelimiter))
            }
            protectedRanges.append(match.range)
        }

        collect(pattern: "(?<!\\*)\\*(?!\\s|\\*)([^*\\n]+?)(?<!\\s)\\*(?!\\*)", in: line, range: fullLocalRange, protectedRanges: protectedRanges) { match in
            if shouldReveal(match.range, focusedRanges: focusedRanges) {
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + match.range.location, length: 1), label: "*", role: .inlineDelimiter))
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + NSMaxRange(match.range) - 1, length: 1), label: "*", role: .inlineDelimiter))
            }
            protectedRanges.append(match.range)
        }

        collect(pattern: "(?<!\\w)_(?!\\s|_)([^_\\n]+?)(?<!\\s)_(?!\\w)", in: line, range: fullLocalRange, protectedRanges: protectedRanges) { match in
            if shouldReveal(match.range, focusedRanges: focusedRanges) {
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + match.range.location, length: 1), label: "_", role: .inlineDelimiter))
                tokens.append(MarkdownAnnotationToken(range: NSRange(location: contentRange.location + NSMaxRange(match.range) - 1, length: 1), label: "_", role: .inlineDelimiter))
            }
            protectedRanges.append(match.range)
        }

        return tokens.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func collect(
        pattern: String,
        in line: String,
        range: NSRange,
        protectedRanges: [NSRange],
        handler: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: line, range: range) {
            guard !protectedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                continue
            }
            handler(match)
        }
    }

    private static func shouldReveal(_ matchRange: NSRange, focusedRanges: [NSRange]) -> Bool {
        focusedRanges.contains { focused in
            if focused.length == 0 {
                return NSLocationInRange(focused.location, matchRange) || focused.location == NSMaxRange(matchRange)
            }
            return NSIntersectionRange(matchRange, focused).length > 0
        }
    }

    private static func firstMatch(pattern: String, in line: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, range: range)
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
