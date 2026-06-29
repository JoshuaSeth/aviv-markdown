import Foundation

public struct MarkdownImageReference: Equatable {
    public let range: NSRange
    public let altRange: NSRange
    public let targetRange: NSRange
    public let altText: String
    public let target: String
    public let source: String

    public init(
        range: NSRange,
        altRange: NSRange,
        targetRange: NSRange,
        altText: String,
        target: String,
        source: String
    ) {
        self.range = range
        self.altRange = altRange
        self.targetRange = targetRange
        self.altText = altText
        self.target = target
        self.source = source
    }
}

public enum MarkdownImageParser {
    public static func images(in markdown: String, range searchRange: NSRange? = nil) -> [MarkdownImageReference] {
        let nsString = markdown as NSString
        guard nsString.length > 0,
              let regex = try? NSRegularExpression(pattern: MarkdownPatterns.image)
        else { return [] }

        let range = searchRange ?? NSRange(location: 0, length: nsString.length)
        return regex.matches(in: markdown, range: range).compactMap { match in
            guard match.range.location != NSNotFound,
                  match.numberOfRanges >= 3
            else { return nil }

            let altRange = match.range(at: 1)
            let targetRange = match.range(at: 2)
            guard altRange.location != NSNotFound,
                  targetRange.location != NSNotFound
            else { return nil }

            return MarkdownImageReference(
                range: match.range,
                altRange: altRange,
                targetRange: targetRange,
                altText: nsString.substring(with: altRange),
                target: nsString.substring(with: targetRange),
                source: nsString.substring(with: match.range)
            )
        }
    }
}

public enum MarkdownImageResolver {
    public static func fileURL(for rawTarget: String, baseURL: URL?) -> URL? {
        let target = cleanedTarget(rawTarget)
        guard !target.isEmpty else { return nil }

        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            return nil
        }

        if target.hasPrefix("file://"),
           let url = URL(string: target) {
            return url
        }

        let expanded = expandingTilde(in: target)
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }

        if let baseURL {
            return baseURL.appendingPathComponent(expanded).standardizedFileURL
        }

        return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    private static func cleanedTarget(_ rawTarget: String) -> String {
        var target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("<"), target.hasSuffix(">"), target.count >= 2 {
            target.removeFirst()
            target.removeLast()
        }
        return target.removingPercentEncoding ?? target
    }

    private static func expandingTilde(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return NSString(string: path).expandingTildeInPath
    }
}
