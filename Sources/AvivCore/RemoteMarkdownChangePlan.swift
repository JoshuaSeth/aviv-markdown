import Foundation

public struct RemoteMarkdownChangePlan: Equatable, Sendable {
    public let oldRange: NSRange
    public let newRange: NSRange

    public init(oldMarkdown: String, newMarkdown: String) {
        let oldUnits = Array(oldMarkdown.utf16)
        let newUnits = Array(newMarkdown.utf16)
        let oldLines = Self.lineRanges(in: oldUnits)
        let newLines = Self.lineRanges(in: newUnits)
        let sharedLineLimit = min(oldLines.count, newLines.count)
        var prefixLineCount = 0
        while prefixLineCount < sharedLineLimit,
            Self.equal(
                oldUnits,
                range: oldLines[prefixLineCount],
                newUnits,
                range: newLines[prefixLineCount]
            )
        {
            prefixLineCount += 1
        }

        var suffixLineCount = 0
        while suffixLineCount
            < min(
                oldLines.count - prefixLineCount,
                newLines.count - prefixLineCount
            ),
            Self.equal(
                oldUnits,
                range: oldLines[oldLines.count - suffixLineCount - 1],
                newUnits,
                range: newLines[newLines.count - suffixLineCount - 1]
            )
        {
            suffixLineCount += 1
        }

        let oldRegionStart = prefixLineCount == 0 ? 0 : NSMaxRange(oldLines[prefixLineCount - 1])
        let newRegionStart = prefixLineCount == 0 ? 0 : NSMaxRange(newLines[prefixLineCount - 1])
        let oldRegionEnd =
            suffixLineCount == 0
            ? oldUnits.count : oldLines[oldLines.count - suffixLineCount].location
        let newRegionEnd =
            suffixLineCount == 0
            ? newUnits.count : newLines[newLines.count - suffixLineCount].location
        let oldRegionLength = oldRegionEnd - oldRegionStart
        let newRegionLength = newRegionEnd - newRegionStart

        let sharedLimit = min(oldRegionLength, newRegionLength)
        var prefixLength = 0
        while prefixLength < sharedLimit,
            oldUnits[oldRegionStart + prefixLength] == newUnits[newRegionStart + prefixLength]
        {
            prefixLength += 1
        }

        var suffixLength = 0
        let remainingOld = oldRegionLength - prefixLength
        let remainingNew = newRegionLength - prefixLength
        while suffixLength < min(remainingOld, remainingNew),
            oldUnits[oldRegionEnd - suffixLength - 1]
                == newUnits[newRegionEnd - suffixLength - 1]
        {
            suffixLength += 1
        }

        oldRange = NSRange(
            location: oldRegionStart + prefixLength,
            length: oldRegionLength - prefixLength - suffixLength
        )
        newRange = NSRange(
            location: newRegionStart + prefixLength,
            length: newRegionLength - prefixLength - suffixLength
        )
    }

    public var hasChanges: Bool {
        oldRange.length != 0 || newRange.length != 0
    }

    public func map(location: Int) -> Int {
        if location < oldRange.location {
            return location
        }
        if location >= NSMaxRange(oldRange) {
            return location + newRange.length - oldRange.length
        }
        let relativeLocation = location - oldRange.location
        return newRange.location + min(relativeLocation, newRange.length)
    }

    private static func lineRanges(in units: [UInt16]) -> [NSRange] {
        guard !units.isEmpty else { return [] }
        var ranges: [NSRange] = []
        var start = 0
        for index in units.indices where units[index] == 10 {
            ranges.append(NSRange(location: start, length: index - start + 1))
            start = index + 1
        }
        if start < units.count {
            ranges.append(NSRange(location: start, length: units.count - start))
        }
        return ranges
    }

    private static func equal(
        _ oldUnits: [UInt16],
        range oldRange: NSRange,
        _ newUnits: [UInt16],
        range newRange: NSRange
    ) -> Bool {
        guard oldRange.length == newRange.length else { return false }
        return oldUnits[oldRange.location..<NSMaxRange(oldRange)]
            .elementsEqual(newUnits[newRange.location..<NSMaxRange(newRange)])
    }

    public func map(range: NSRange, newMarkdown: String) -> NSRange {
        let mappedStart = map(location: range.location)
        let mappedEnd = map(location: NSMaxRange(range))
        let documentLength = (newMarkdown as NSString).length
        let start = min(max(0, mappedStart), documentLength)
        let end = min(max(start, mappedEnd), documentLength)
        return NSRange(location: start, length: end - start)
    }

    public func changedLineRanges(in newMarkdown: String) -> [NSRange] {
        lineRanges(in: newMarkdown, changedRange: newRange)
    }

    public func changedOldLineRanges(in oldMarkdown: String) -> [NSRange] {
        lineRanges(in: oldMarkdown, changedRange: oldRange)
    }

    private func lineRanges(in markdown: String, changedRange: NSRange) -> [NSRange] {
        let text = markdown as NSString
        guard text.length > 0 else { return [] }
        let location = min(changedRange.location, text.length - 1)
        let available = text.length - location
        let length = min(max(1, changedRange.length), available)
        let changedLines = text.lineRange(for: NSRange(location: location, length: length))
        var ranges: [NSRange] = []
        var cursor = changedLines.location
        while cursor < NSMaxRange(changedLines) {
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            ranges.append(line)
            let next = NSMaxRange(line)
            guard next > cursor else { break }
            cursor = next
        }
        return ranges
    }
}
