import AppKit

public final class MarkdownStyler {
    public var theme: MarkdownTheme

    public init(theme: MarkdownTheme = .clean) {
        self.theme = theme
    }

    public func attributedString(for markdown: String, selectedRanges: [NSRange] = []) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(string: markdown)
        let fullRange = NSRange(location: 0, length: (markdown as NSString).length)
        guard fullRange.length > 0 else {
            return attributed
        }

        attributed.setAttributes(theme.baseAttributes, range: fullRange)
        applyBlockAndInlineStyles(to: attributed, selectedRanges: selectedRanges)
        return attributed
    }

    public func apply(to textStorage: NSTextStorage, selectedRanges: [NSRange]) {
        let markdown = textStorage.string
        let fullRange = NSRange(location: 0, length: (markdown as NSString).length)
        guard fullRange.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.setAttributes(theme.baseAttributes, range: fullRange)
        applyBlockAndInlineStyles(to: textStorage, selectedRanges: selectedRanges)
        textStorage.endEditing()
    }

    public func apply(to textStorage: NSTextStorage, selectedRanges: [NSRange], affectedRanges: [NSRange]) {
        let nsString = textStorage.string as NSString
        guard nsString.length > 0,
              let styleRange = expandedLineRange(covering: affectedRanges + selectedRanges, in: nsString)
        else {
            return
        }

        textStorage.beginEditing()
        textStorage.setAttributes(theme.baseAttributes, range: styleRange)
        applyBlockAndInlineStyles(to: textStorage, selectedRanges: selectedRanges, limitRange: styleRange)
        textStorage.endEditing()
    }

    private func applyBlockAndInlineStyles(
        to attributed: NSMutableAttributedString,
        selectedRanges: [NSRange],
        limitRange: NSRange? = nil
    ) {
        let nsString = attributed.string as NSString
        let tableRows = limitRange == nil ? MarkdownTableParser.rowMap(in: attributed.string) : [:]
        let styleLimit = limitRange.map { NSIntersectionRange($0, NSRange(location: 0, length: nsString.length)) }
        let upperBound = styleLimit.map { NSMaxRange($0) } ?? nsString.length
        var index = styleLimit.map { lineRange(containing: $0.location, in: nsString).location } ?? 0
        var insideFence = styleLimit == nil ? false : isInsideFence(at: index, in: nsString)

        while index < nsString.length, index < upperBound {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let contentRange = rangeWithoutLineEnding(lineRange, in: nsString)
            let line = nsString.substring(with: contentRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isActive = isLineActive(lineRange, selectedRanges: selectedRanges, documentLength: nsString.length)

            if isFence(trimmed) {
                applyCodeBlockStyle(to: attributed, lineRange: lineRange, contentRange: contentRange)
                applySyntax(NSRange(location: contentRange.location, length: contentRange.length), active: isActive, to: attributed)
                insideFence.toggle()
                index = NSMaxRange(lineRange)
                continue
            }

            if insideFence {
                applyCodeBlockStyle(to: attributed, lineRange: lineRange, contentRange: contentRange)
                index = NSMaxRange(lineRange)
                continue
            }

            if let tableRow = tableRows[contentRange.location] {
                applyTableStyle(
                    to: attributed,
                    lineRange: lineRange,
                    contentRange: contentRange,
                    row: tableRow,
                    lineActive: isActive
                )
                index = NSMaxRange(lineRange)
                continue
            }

            if let heading = parseHeading(line: line, contentRange: contentRange) {
                applyHeading(level: heading.level, to: attributed, lineRange: lineRange, contentRange: contentRange)
                applySyntax(heading.syntaxRange, active: isActive, to: attributed)
                applyInlineStyles(to: attributed, searchRange: heading.bodyRange, lineActive: isActive)
            } else if isHorizontalRule(trimmed) {
                applyHorizontalRule(to: attributed, lineRange: lineRange, contentRange: contentRange)
            } else if let task = parseTaskList(line: line, contentRange: contentRange) {
                applyListStyle(to: attributed, lineRange: lineRange, contentRange: contentRange)
                applySyntax(task.prefixRange, active: isActive, to: attributed)
                applyTaskMarkerStyle(task.checkboxRange, checked: task.checked, active: isActive, to: attributed)
                applyInlineStyles(to: attributed, searchRange: task.bodyRange, lineActive: isActive)
            } else if let list = parseList(line: line, contentRange: contentRange) {
                applyListStyle(to: attributed, lineRange: lineRange, contentRange: contentRange)
                applyVisibleSourceMarker(list.syntaxRange, to: attributed)
                applyInlineStyles(to: attributed, searchRange: list.bodyRange, lineActive: isActive)
            } else if let quote = parseBlockquote(line: line, contentRange: contentRange) {
                applyQuoteStyle(to: attributed, lineRange: lineRange, contentRange: contentRange)
                applyVisibleSourceMarker(quote.syntaxRange, to: attributed)
                applyInlineStyles(to: attributed, searchRange: quote.bodyRange, lineActive: isActive)
            } else {
                applyInlineStyles(to: attributed, searchRange: contentRange, lineActive: isActive)
            }

            index = NSMaxRange(lineRange)
        }
    }

    private func applyHeading(level: Int, to attributed: NSMutableAttributedString, lineRange: NSRange, contentRange: NSRange) {
        let paragraphStyle = theme.paragraphStyle(
            lineSpacing: 4,
            paragraphSpacing: level <= 2 ? 16 : 13,
            paragraphSpacingBefore: level <= 2 ? 15 : 8
        )
        attributed.addAttributes([
            .font: theme.headingFont(level: level),
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ], range: lineRange)
        if contentRange.length > 0 {
            attributed.addAttribute(.font, value: theme.headingFont(level: level), range: contentRange)
        }
    }

    private func applyListStyle(to attributed: NSMutableAttributedString, lineRange: NSRange, contentRange: NSRange) {
        attributed.addAttribute(.paragraphStyle, value: theme.paragraphStyle(firstLineHeadIndent: 0, headIndent: 24), range: lineRange)
        if contentRange.length > 0 {
            attributed.addAttribute(.foregroundColor, value: theme.textColor, range: contentRange)
        }
    }

    private func applyQuoteStyle(to attributed: NSMutableAttributedString, lineRange: NSRange, contentRange: NSRange) {
        attributed.addAttributes([
            .paragraphStyle: theme.paragraphStyle(lineSpacing: 5, paragraphSpacing: 12, firstLineHeadIndent: 0, headIndent: 18),
            .foregroundColor: theme.secondaryTextColor
        ], range: lineRange)
        if contentRange.length > 0 {
            attributed.addAttribute(.obliqueness, value: 0.08, range: contentRange)
        }
    }

    private func applyCodeBlockStyle(to attributed: NSMutableAttributedString, lineRange: NSRange, contentRange: NSRange) {
        attributed.addAttributes([
            .font: theme.codeFont,
            .foregroundColor: theme.textColor,
            .backgroundColor: theme.codeBackgroundColor,
            .paragraphStyle: theme.paragraphStyle(lineSpacing: 3, paragraphSpacing: 0)
        ], range: lineRange)
        if contentRange.length > 0 {
            attributed.addAttributes([
                .font: theme.codeFont,
                .foregroundColor: theme.textColor
            ], range: contentRange)
        }
    }

    private func applyHorizontalRule(to attributed: NSMutableAttributedString, lineRange: NSRange, contentRange: NSRange) {
        attributed.addAttributes([
            .font: theme.bodyFont,
            .foregroundColor: theme.syntaxVisibleColor,
            .paragraphStyle: theme.paragraphStyle(lineSpacing: 2, paragraphSpacing: 18, paragraphSpacingBefore: 10)
        ], range: lineRange)
        if contentRange.length > 0 {
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
        }
    }

    private func applyTableStyle(
        to attributed: NSMutableAttributedString,
        lineRange: NSRange,
        contentRange: NSRange,
        row: MarkdownTableRow,
        lineActive: Bool
    ) {
        attributed.addAttributes([
            .font: theme.codeFont,
            .paragraphStyle: theme.paragraphStyle(lineSpacing: 3, paragraphSpacing: 4),
            .foregroundColor: theme.textColor
        ], range: lineRange)

        if !lineActive {
            if row.isSeparator {
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = 1
                paragraph.maximumLineHeight = 1
                paragraph.lineSpacing = 0
                paragraph.paragraphSpacing = 0
                attributed.addAttributes([
                    .font: NSFont.systemFont(ofSize: 0.01),
                    .paragraphStyle: paragraph.copy() as! NSParagraphStyle
                ], range: lineRange)
            }
            attributed.addAttributes([
                .foregroundColor: theme.syntaxHiddenColor
            ], range: contentRange)
            return
        }

        let nsString = attributed.string as NSString
        for offset in 0..<contentRange.length {
            let location = contentRange.location + offset
            let character = nsString.substring(with: NSRange(location: location, length: 1))
            if character == "|" {
                attributed.addAttribute(.foregroundColor, value: theme.syntaxVisibleColor, range: NSRange(location: location, length: 1))
            } else if character == "-" || character == ":" {
                attributed.addAttribute(.foregroundColor, value: theme.secondaryTextColor, range: NSRange(location: location, length: 1))
            }
        }
        if !row.isSeparator {
            applyInlineStyles(to: attributed, searchRange: contentRange, lineActive: lineActive, renderImages: false)
        }
    }

    private func applyTaskMarkerStyle(_ range: NSRange, checked: Bool, active: Bool, to attributed: NSMutableAttributedString) {
        guard range.length > 0 else { return }
        attributed.addAttributes([
            .font: theme.codeFont,
            .foregroundColor: active ? theme.syntaxVisibleColor : (checked ? theme.accentColor : theme.secondaryTextColor)
        ], range: range)
    }

    private func applyInlineStyles(
        to attributed: NSMutableAttributedString,
        searchRange: NSRange,
        lineActive: Bool,
        renderImages: Bool = true
    ) {
        guard searchRange.length > 0 else { return }

        var protectedRanges: [NSRange] = []

        if renderImages {
            applyMatches(pattern: MarkdownPatterns.image, to: attributed, in: searchRange, protectedRanges: &protectedRanges) { match in
                self.applyImageSourceStyle(match.range, to: attributed)
                return [match.range]
            }
        }

        applyMatches(pattern: "`([^`\\n]+)`", to: attributed, in: searchRange, protectedRanges: &protectedRanges) { match in
            let content = match.range(at: 1)
            self.applySyntax(NSRange(location: match.range.location, length: 1), active: lineActive, to: attributed)
            self.applySyntax(NSRange(location: NSMaxRange(match.range) - 1, length: 1), active: lineActive, to: attributed)
            attributed.addAttributes([
                .font: self.theme.codeFont,
                .foregroundColor: self.theme.textColor,
                .backgroundColor: self.theme.codeBackgroundColor
            ], range: content)
            return [match.range]
        }

        applyMatches(pattern: MarkdownPatterns.link, to: attributed, in: searchRange, protectedRanges: &protectedRanges) { match in
            let textRange = match.range(at: 1)
            let targetRange = match.range(at: 2)
            attributed.addAttributes([
                .foregroundColor: self.theme.accentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: textRange)

            let prefixLength = textRange.location - match.range.location
            self.applySyntax(NSRange(location: match.range.location, length: prefixLength), active: lineActive, to: attributed)
            let middleStart = NSMaxRange(textRange)
            self.applySyntax(NSRange(location: middleStart, length: targetRange.location - middleStart), active: lineActive, to: attributed)
            self.applySyntax(targetRange, active: lineActive, to: attributed)
            self.applySyntax(NSRange(location: NSMaxRange(targetRange), length: NSMaxRange(match.range) - NSMaxRange(targetRange)), active: lineActive, to: attributed)
            return [match.range]
        }

        applyMatches(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1", to: attributed, in: searchRange, protectedRanges: &protectedRanges) { match in
            let delimiter = match.range(at: 1)
            let content = match.range(at: 2)
            self.applyFontTrait(.boldFontMask, to: attributed, range: content)
            self.applySyntax(delimiter, active: lineActive, to: attributed)
            self.applySyntax(NSRange(location: NSMaxRange(content), length: delimiter.length), active: lineActive, to: attributed)
            return [match.range]
        }

        applyMatches(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)~~", to: attributed, in: searchRange, protectedRanges: &protectedRanges) { match in
            let delimiter = match.range(at: 1)
            let content = match.range(at: 2)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            self.applySyntax(delimiter, active: lineActive, to: attributed)
            self.applySyntax(NSRange(location: NSMaxRange(content), length: delimiter.length), active: lineActive, to: attributed)
            return [match.range]
        }

        applyMatches(pattern: "(?<!\\*)\\*(?!\\s|\\*)([^*\\n]+?)(?<!\\s)\\*(?!\\*)", to: attributed, in: searchRange, protectedRanges: &protectedRanges) { match in
            let content = match.range(at: 1)
            self.applyFontTrait(.italicFontMask, to: attributed, range: content)
            self.applySyntax(NSRange(location: match.range.location, length: 1), active: lineActive, to: attributed)
            self.applySyntax(NSRange(location: NSMaxRange(match.range) - 1, length: 1), active: lineActive, to: attributed)
            return [match.range]
        }

        applyMatches(pattern: "(?<!\\w)_(?!\\s|_)([^_\\n]+?)(?<!\\s)_(?!\\w)", to: attributed, in: searchRange, protectedRanges: &protectedRanges) { match in
            let content = match.range(at: 1)
            self.applyFontTrait(.italicFontMask, to: attributed, range: content)
            self.applySyntax(NSRange(location: match.range.location, length: 1), active: lineActive, to: attributed)
            self.applySyntax(NSRange(location: NSMaxRange(match.range) - 1, length: 1), active: lineActive, to: attributed)
            return [match.range]
        }
    }

    private func applyImageSourceStyle(_ range: NSRange, to attributed: NSMutableAttributedString) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        let nsString = attributed.string as NSString
        let lineRange = nsString.lineRange(for: range)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = theme.scaledMetric(324, minimum: 208)
        paragraph.maximumLineHeight = theme.scaledMetric(324, minimum: 208)
        paragraph.paragraphSpacing = theme.scaledMetric(14, minimum: 9)
        paragraph.paragraphSpacingBefore = theme.scaledMetric(4, minimum: 2)

        attributed.addAttribute(.paragraphStyle, value: paragraph.copy() as! NSParagraphStyle, range: lineRange)
        attributed.addAttributes([
            .foregroundColor: theme.syntaxHiddenColor,
            .font: NSFont.systemFont(ofSize: 0.01),
            .kern: 0
        ], range: range)
    }

    private func applyMatches(
        pattern: String,
        to attributed: NSMutableAttributedString,
        in searchRange: NSRange,
        protectedRanges: inout [NSRange],
        handler: (NSTextCheckingResult) -> [NSRange]
    ) {
        guard let regex = MarkdownStylerRegex.regex(for: pattern) else { return }
        applyMatches(
            regex: regex,
            to: attributed,
            in: searchRange,
            protectedRanges: &protectedRanges,
            handler: handler
        )
    }

    private func applyMatches(
        regex: NSRegularExpression,
        to attributed: NSMutableAttributedString,
        in searchRange: NSRange,
        protectedRanges: inout [NSRange],
        handler: (NSTextCheckingResult) -> [NSRange]
    ) {
        let string = attributed.string
        let matches = regex.matches(in: string, range: searchRange)
        for match in matches where match.range.location != NSNotFound {
            if protectedRanges.contains(where: { rangesIntersect($0, match.range) }) {
                continue
            }
            let newlyProtected = handler(match)
            protectedRanges.append(contentsOf: newlyProtected)
        }
    }

    private func applySyntax(_ range: NSRange, active: Bool, to attributed: NSMutableAttributedString) {
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= attributed.length else { return }
        attributed.addAttributes([
            .foregroundColor: theme.syntaxHiddenColor,
            .font: NSFont.systemFont(ofSize: 0.01),
            .kern: 0
        ], range: range)
    }

    private func applyVisibleSourceMarker(_ range: NSRange, to attributed: NSMutableAttributedString) {
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= attributed.length else { return }
        attributed.addAttributes([
            .foregroundColor: theme.syntaxVisibleColor,
            .font: theme.bodyFont
        ], range: range)
    }

    private func applyFontTrait(_ trait: NSFontTraitMask, to attributed: NSMutableAttributedString, range: NSRange) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? theme.bodyFont
            let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            attributed.addAttribute(.font, value: converted, range: subrange)
        }
    }

    private func parseHeading(line: String, contentRange: NSRange) -> (level: Int, syntaxRange: NSRange, bodyRange: NSRange)? {
        var level = 0
        for scalar in line.unicodeScalars {
            if scalar == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level), line.count > level else { return nil }
        let index = line.index(line.startIndex, offsetBy: level)
        guard line[index] == " " else { return nil }
        let syntaxLength = level + 1
        let bodyLength = max(0, contentRange.length - syntaxLength)
        return (
            level,
            NSRange(location: contentRange.location, length: syntaxLength),
            NSRange(location: contentRange.location + syntaxLength, length: bodyLength)
        )
    }

    private func parseTaskList(line: String, contentRange: NSRange) -> (prefixRange: NSRange, checkboxRange: NSRange, bodyRange: NSRange, checked: Bool)? {
        guard let match = firstMatch(regex: MarkdownStylerRegex.taskList, in: line) else { return nil }
        let prefix = match.range(at: 1)
        let checkbox = match.range(at: 2)
        let full = match.range(at: 0)
        let bodyStart = contentRange.location + full.length
        let bodyLength = max(0, contentRange.length - full.length)
        let checkboxText = (line as NSString).substring(with: checkbox)
        return (
            NSRange(location: contentRange.location + prefix.location, length: prefix.length),
            NSRange(location: contentRange.location + checkbox.location, length: checkbox.length),
            NSRange(location: bodyStart, length: bodyLength),
            checkboxText.lowercased().contains("x")
        )
    }

    private func parseList(line: String, contentRange: NSRange) -> (syntaxRange: NSRange, bodyRange: NSRange)? {
        guard let match = firstMatch(regex: MarkdownStylerRegex.list, in: line) else { return nil }
        let full = match.range(at: 0)
        let bodyStart = contentRange.location + full.length
        return (
            NSRange(location: contentRange.location, length: full.length),
            NSRange(location: bodyStart, length: max(0, contentRange.length - full.length))
        )
    }

    private func parseBlockquote(line: String, contentRange: NSRange) -> (syntaxRange: NSRange, bodyRange: NSRange)? {
        guard let match = firstMatch(regex: MarkdownStylerRegex.blockquote, in: line) else { return nil }
        let full = match.range(at: 0)
        let bodyStart = contentRange.location + full.length
        return (
            NSRange(location: contentRange.location, length: full.length),
            NSRange(location: bodyStart, length: max(0, contentRange.length - full.length))
        )
    }

    private func firstMatch(regex: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, range: range)
    }

    private func isFence(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private func isHorizontalRule(_ trimmedLine: String) -> Bool {
        guard trimmedLine.count >= 3 else { return false }
        let characters = Set(trimmedLine)
        return characters == ["-"] || characters == ["*"] || characters == ["_"]
    }

    private func isLineActive(_ lineRange: NSRange, selectedRanges: [NSRange], documentLength: Int) -> Bool {
        guard !selectedRanges.isEmpty else { return false }
        for selection in selectedRanges {
            if selection.length == 0 {
                if NSLocationInRange(selection.location, lineRange) || (selection.location == documentLength && NSMaxRange(lineRange) == documentLength) {
                    return true
                }
            } else if rangesIntersect(lineRange, selection) {
                return true
            }
        }
        return false
    }

    private func isInsideFence(at location: Int, in nsString: NSString) -> Bool {
        var index = 0
        var insideFence = false
        while index < min(location, nsString.length) {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let contentRange = rangeWithoutLineEnding(lineRange, in: nsString)
            let trimmed = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespaces)
            if isFence(trimmed) {
                insideFence.toggle()
            }
            index = NSMaxRange(lineRange)
        }
        return insideFence
    }

    private func expandedLineRange(covering ranges: [NSRange], in nsString: NSString) -> NSRange? {
        var result: NSRange?
        for range in ranges {
            guard range.location != NSNotFound else { continue }
            let lineRange = lineRange(containing: range.location, length: range.length, in: nsString)
            result = result.map { NSUnionRange($0, lineRange) } ?? lineRange
        }
        return result
    }

    private func lineRange(containing location: Int, length: Int = 0, in nsString: NSString) -> NSRange {
        guard nsString.length > 0 else { return NSRange(location: 0, length: 0) }
        let boundedLocation = min(max(0, location), max(0, nsString.length - 1))
        let boundedLength = min(max(0, length), nsString.length - boundedLocation)
        let target = NSRange(location: boundedLocation, length: boundedLength)
        return nsString.lineRange(for: target)
    }

    private func rangeWithoutLineEnding(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
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

private func rangesIntersect(_ first: NSRange, _ second: NSRange) -> Bool {
    NSIntersectionRange(first, second).length > 0
}

private enum MarkdownStylerRegex {
    static let image = try! NSRegularExpression(pattern: MarkdownPatterns.image)
    static let inlineCode = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    static let link = try! NSRegularExpression(pattern: MarkdownPatterns.link)
    static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    static let strike = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)~~")
    static let italicAsterisk = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\s|\\*)([^*\\n]+?)(?<!\\s)\\*(?!\\*)")
    static let italicUnderscore = try! NSRegularExpression(pattern: "(?<!\\w)_(?!\\s|_)([^_\\n]+?)(?<!\\s)_(?!\\w)")
    static let taskList = try! NSRegularExpression(pattern: #"^(\s*(?:[-+*]|\d+[.)])\s+)(\[[ xX]\])\s+"#)
    static let list = try! NSRegularExpression(pattern: #"^\s*(?:[-+*]|\d+[.)])\s+"#)
    static let blockquote = try! NSRegularExpression(pattern: #"^\s*>\s?"#)

    static func regex(for pattern: String) -> NSRegularExpression? {
        switch pattern {
        case MarkdownPatterns.image:
            return image
        case "`([^`\\n]+)`":
            return inlineCode
        case MarkdownPatterns.link:
            return link
        case "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1":
            return bold
        case "(~~)(?=\\S)(.+?)(?<=\\S)~~":
            return strike
        case "(?<!\\*)\\*(?!\\s|\\*)([^*\\n]+?)(?<!\\s)\\*(?!\\*)":
            return italicAsterisk
        case "(?<!\\w)_(?!\\s|_)([^_\\n]+?)(?<!\\s)_(?!\\w)":
            return italicUnderscore
        default:
            return try? NSRegularExpression(pattern: pattern)
        }
    }
}
