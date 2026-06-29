import AppKit

public final class MarkdownAnnotationOverlayView: NSView {
    public weak var textView: MarkdownTextView?
    private let fallbackTheme: MarkdownTheme

    public init(textView: MarkdownTextView, theme: MarkdownTheme = .clean) {
        self.textView = textView
        self.fallbackTheme = theme
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool {
        true
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let ranges = textView.selectedRanges.compactMap { $0.rangeValue }
        drawTables(in: textView, layoutManager: layoutManager, textContainer: textContainer, selectedRanges: ranges)

        let tokens = MarkdownAnnotationParser.tokens(in: textView.string, selectedRanges: ranges)
        guard !tokens.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)

        var occupiedRects: [NSRect] = []
        for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
            guard token.range.location != NSNotFound, token.range.location < textView.string.utf16.count else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
            let effectiveGlyphRange = glyphRange.length > 0 ? glyphRange : NSRange(location: min(glyphRange.location, max(0, layoutManager.numberOfGlyphs - 1)), length: 1)
            var rect = layoutManager.boundingRect(forGlyphRange: effectiveGlyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            rect = textView.convert(rect, to: self)
            let drawRect = annotationRect(for: token, near: rect, occupiedRects: occupiedRects)
            occupiedRects.append(drawRect.insetBy(dx: -4, dy: -2))
            draw(token: token, in: drawRect)
        }
    }

    private func drawTables(
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        selectedRanges: [NSRange]
    ) {
        let blocks = MarkdownTableParser.blocks(in: textView.string)
        guard !blocks.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)

        for block in blocks {
            draw(block: block, in: textView, layoutManager: layoutManager, textContainer: textContainer, selectedRanges: selectedRanges)
        }
    }

    private func draw(
        block: MarkdownTableBlock,
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        selectedRanges: [NSRange]
    ) {
        let visibleRows = block.rows.filter { !$0.isSeparator }
        guard !visibleRows.isEmpty else { return }
        let theme = currentTheme

        let rowRects = block.rows.map { row -> NSRect in
            rect(for: row.contentRange, textView: textView, layoutManager: layoutManager, textContainer: textContainer)
        }
        guard let firstRect = rowRects.first else { return }

        let columnCount = max(visibleRows.map { $0.cells.count }.max() ?? 0, 1)
        let padding = theme.scaledMetric(14, minimum: 9)
        let font = theme.codeFont
        let headerFont = NSFont.monospacedSystemFont(ofSize: theme.scaledMetric(15, minimum: 10), weight: .semibold)
        var columnWidths = Array(repeating: theme.scaledMetric(88, minimum: 58), count: columnCount)

        for row in visibleRows {
            for (index, cell) in row.cells.enumerated() where index < columnWidths.count {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: row.isHeader ? headerFont : font
                ]
                let width = ceil((cell.text as NSString).size(withAttributes: attributes).width) + padding * 2
                columnWidths[index] = max(columnWidths[index], min(width, theme.scaledMetric(560, minimum: 360)))
            }
        }

        let maxWidth = max(theme.scaledMetric(300, minimum: 220), textContainer.containerSize.width - theme.scaledMetric(18, minimum: 12))
        let naturalWidth = columnWidths.reduce(0, +)
        if naturalWidth > maxWidth {
            let scale = maxWidth / naturalWidth
            columnWidths = columnWidths.map { max(theme.scaledMetric(72, minimum: 48), floor($0 * scale)) }
        } else if naturalWidth < maxWidth, columnWidths.count > 1 {
            columnWidths[columnWidths.count - 1] += floor(maxWidth - naturalWidth)
        }

        let tableWidth = columnWidths.reduce(0, +)
        let tableX = firstRect.minX
        var rowFrames: [Int: NSRect] = [:]

        for index in block.rows.indices {
            let rect = rowRects[index]
            let height = max(theme.scaledMetric(30, minimum: 20), rect.height + theme.scaledMetric(8, minimum: 5))
            rowFrames[index] = NSRect(x: tableX, y: rect.minY - theme.scaledMetric(3, minimum: 2), width: tableWidth, height: height)
        }

        for (index, row) in block.rows.enumerated() {
            guard let frame = rowFrames[index] else { continue }
            let active = selectedRanges.contains { selection in
                if selection.length == 0 {
                    return NSLocationInRange(selection.location, row.lineRange)
                }
                return NSIntersectionRange(selection, row.lineRange).length > 0
            }

            if row.isSeparator {
                theme.secondaryTextColor.withAlphaComponent(0.35).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: frame.minX, y: frame.midY))
                path.line(to: NSPoint(x: frame.maxX, y: frame.midY))
                path.lineWidth = 1
                path.stroke()
                continue
            }

            let fillColor: NSColor
            if row.isHeader {
                fillColor = NSColor(calibratedRed: 0.956, green: 0.962, blue: 0.966, alpha: 0.94)
            } else if active {
                fillColor = NSColor(calibratedRed: 0.970, green: 0.978, blue: 0.982, alpha: 0.14)
            } else {
                fillColor = index.isMultiple(of: 2)
                    ? NSColor(calibratedWhite: 1.0, alpha: 0.72)
                    : NSColor(calibratedRed: 0.980, green: 0.982, blue: 0.978, alpha: 0.70)
            }
            fillColor.setFill()
            NSBezierPath(rect: frame).fill()

            theme.secondaryTextColor.withAlphaComponent(0.20).setStroke()
            NSBezierPath(rect: frame).stroke()

            var cellX = frame.minX
            for column in 0..<columnCount {
                if column > 0 {
                    let separator = NSBezierPath()
                    separator.move(to: NSPoint(x: cellX, y: frame.minY))
                    separator.line(to: NSPoint(x: cellX, y: frame.maxY))
                    separator.lineWidth = 1
                    separator.stroke()
                }

                if !active, column < row.cells.count {
                    let cell = row.cells[column]
                    let displayText = renderedCellText(cell.text)
                    let drawRect = NSRect(
                        x: cellX + padding,
                        y: frame.minY + theme.scaledMetric(6, minimum: 4),
                        width: max(8, columnWidths[column] - padding * 2),
                        height: max(10, frame.height - theme.scaledMetric(10, minimum: 7))
                    )
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: row.isHeader ? headerFont : font,
                        .foregroundColor: row.isHeader ? theme.textColor : theme.textColor.withAlphaComponent(0.92),
                        .kern: 0
                    ]
                    (displayText as NSString).draw(in: drawRect, withAttributes: attributes)
                }

                cellX += columnWidths[column]
            }
        }
    }

    private func rect(
        for range: NSRange,
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        let safeRange: NSRange
        if range.length > 0 {
            safeRange = range
        } else {
            safeRange = NSRange(location: min(range.location, max(0, layoutManager.numberOfGlyphs - 1)), length: 1)
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: safeRange, actualCharacterRange: nil)
        let effectiveGlyphRange = glyphRange.length > 0 ? glyphRange : NSRange(location: min(glyphRange.location, max(0, layoutManager.numberOfGlyphs - 1)), length: 1)
        var rect = layoutManager.boundingRect(forGlyphRange: effectiveGlyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return textView.convert(rect, to: self)
    }

    private func annotationRect(for token: MarkdownAnnotationToken, near rect: NSRect, occupiedRects: [NSRect]) -> NSRect {
        let size = annotationSize(for: token)
        var origin: NSPoint
        let theme = currentTheme

        switch token.role {
        case .heading:
            origin = NSPoint(x: max(8, rect.minX - size.width - theme.scaledMetric(9, minimum: 6)), y: rect.minY + theme.scaledMetric(8, minimum: 5))
        case .linkSource:
            origin = NSPoint(x: max(8, rect.minX), y: max(0, rect.minY - size.height - theme.scaledMetric(7, minimum: 5)))
        case .linkTarget:
            origin = NSPoint(x: rect.minX + theme.scaledMetric(2, minimum: 1), y: max(0, rect.minY - size.height - theme.scaledMetric(1, minimum: 1)))
        case .codeFence:
            origin = NSPoint(x: rect.minX, y: rect.minY)
        case .inlineDelimiter:
            origin = NSPoint(x: rect.minX, y: max(0, rect.minY - size.height + 1))
        }

        var proposed = NSRect(origin: origin, size: size)
        while occupiedRects.contains(where: { $0.intersects(proposed) }) {
            proposed.origin.y = max(0, proposed.origin.y - proposed.height - theme.scaledMetric(3, minimum: 2))
        }
        return proposed
    }

    private func annotationSize(for token: MarkdownAnnotationToken) -> NSSize {
        let theme = currentTheme
        let font = annotationFont(for: token)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: 0
        ]
        let size = (token.label as NSString).size(withAttributes: attributes)
        if token.role == .linkSource {
            return NSSize(
                width: min(theme.scaledMetric(460, minimum: 300), ceil(size.width) + theme.scaledMetric(12, minimum: 8)),
                height: ceil(size.height) + theme.scaledMetric(5, minimum: 3)
            )
        }
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func draw(token: MarkdownAnnotationToken, in rect: NSRect) {
        let theme = currentTheme
        let font = annotationFont(for: token)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.syntaxVisibleColor,
            .kern: 0
        ]

        if token.role == .linkSource || token.role == .linkTarget {
            NSColor(calibratedWhite: 1.0, alpha: 0.82).setFill()
            let radius = theme.scaledMetric(4, minimum: 2.5)
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }

        let drawRect = token.role == .linkSource
            ? rect.insetBy(dx: theme.scaledMetric(6, minimum: 4), dy: theme.scaledMetric(2, minimum: 1.5))
            : rect
        (token.label as NSString).draw(in: drawRect, withAttributes: attributes)
    }

    private func annotationFont(for token: MarkdownAnnotationToken) -> NSFont {
        let theme = currentTheme
        switch token.role {
        case .linkSource, .linkTarget:
            return NSFont.monospacedSystemFont(ofSize: theme.scaledMetric(10.5, minimum: 8), weight: .medium)
        default:
            return NSFont.monospacedSystemFont(ofSize: theme.scaledMetric(11.5, minimum: 8.5), weight: .medium)
        }
    }

    private var currentTheme: MarkdownTheme {
        textView?.styler.theme ?? fallbackTheme
    }

    private func renderedCellText(_ text: String) -> String {
        var output = text
        let replacements: [(String, String)] = [
            (MarkdownPatterns.link, "$1"),
            (#"`([^`\n]+)`"#, "$1"),
            (#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, "$2"),
            (#"(~~)(?=\S)(.+?)(?<=\S)~~"#, "$2"),
            (#"(?<!\*)\*(?!\s|\*)([^*\n]+?)(?<!\s)\*(?!\*)"#, "$1"),
            (#"(?<!\w)_(?!\s|_)([^_\n]+?)(?<!\s)_(?!\w)"#, "$1")
        ]

        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: (output as NSString).length)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: template)
        }

        return output.replacingOccurrences(of: #"\\|"#, with: "|")
    }
}
