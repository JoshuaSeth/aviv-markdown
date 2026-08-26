import Foundation

public struct MarkdownSearchIndex: Equatable, Sendable {
    public let query: String
    public let matchRanges: [NSRange]

    public init(markdown: String, query: String) {
        self.query = query
        self.matchRanges = Self.findMatches(in: markdown, query: query)
    }

    public static func findMatches(in markdown: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        let source = markdown as NSString
        let queryLength = (query as NSString).length
        guard source.length > 0, queryLength > 0 else { return [] }

        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var matches: [NSRange] = []
        var searchLocation = 0

        while searchLocation < source.length {
            let remaining = NSRange(
                location: searchLocation,
                length: source.length - searchLocation
            )
            let match = source.range(of: query, options: options, range: remaining)
            guard match.location != NSNotFound else { break }

            matches.append(match)
            searchLocation = NSMaxRange(match)
            if match.length == 0 {
                searchLocation += 1
            }
        }

        return matches
    }

    public static func outlineHitItemIndexes(
        outlineItems: [MarkdownDocumentOutlineItem],
        matchRanges: [NSRange],
        documentLength: Int
    ) -> IndexSet {
        guard !outlineItems.isEmpty, !matchRanges.isEmpty else { return [] }

        let sortedMatches = matchRanges.sorted {
            if $0.location == $1.location { return $0.length < $1.length }
            return $0.location < $1.location
        }
        var highlighted = IndexSet()

        for (index, item) in outlineItems.enumerated() {
            let range: NSRange
            switch item.kind {
            case .heading(let level):
                let nextSectionLocation =
                    outlineItems[(index + 1)...].first { candidate in
                        guard case .heading(let candidateLevel) = candidate.kind else {
                            return false
                        }
                        return candidateLevel <= level
                    }?.sourceRange.location ?? documentLength
                range = NSRange(
                    location: item.sourceRange.location,
                    length: max(0, nextSectionLocation - item.sourceRange.location)
                )
            case .table, .unorderedList, .orderedList, .taskList:
                range = item.sourceRange
            }

            if sortedMatchesContainIntersection(sortedMatches, with: range) {
                highlighted.insert(index)
            }
        }

        return highlighted
    }

    private static func sortedMatchesContainIntersection(
        _ matches: [NSRange],
        with range: NSRange
    ) -> Bool {
        let rangeEnd = NSMaxRange(range)
        var lowerBound = 0
        var upperBound = matches.count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if NSMaxRange(matches[middle]) <= range.location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        guard matches.indices.contains(lowerBound) else { return false }
        let match = matches[lowerBound]
        return match.location < rangeEnd
    }
}
