import AppKit
import CoreText

public final class MarkdownAnnotationOverlayView: NSView {
    public weak var textView: MarkdownTextView?
    private let fallbackTheme: MarkdownTheme
    private var tableLayoutRevision = -1
    private var tableColumnWidths: [TableLayoutKey: [CGFloat]] = [:]
    private var tableCellLines: [TableCellLineKey: CTLine] = [:]
    private weak var drawingTargetView: NSView?
    private static let renderedCellReplacements: [(NSRegularExpression, String)] = [
        (cellRegex(MarkdownPatterns.image), "$1"),
        (cellRegex(MarkdownPatterns.link), "$1"),
        (cellRegex(#"`([^`\n]+)`"#), "$1"),
        (cellRegex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#), "$2"),
        (cellRegex(#"(~~)(?=\S)(.+?)(?<=\S)~~"#), "$2"),
        (cellRegex(#"(?<!\*)\*(?!\s|\*)([^*\n]+?)(?<!\s)\*(?!\*)"#), "$1"),
        (cellRegex(#"(?<!\w)_(?!\s|_)([^_\n]+?)(?<!\s)_(?!\w)"#), "$1"),
    ]

    private struct TableLayoutKey: Hashable {
        let blockLocation: Int
        let containerWidth: CGFloat
        let viewScale: CGFloat
    }

    private struct TableCellLineKey: Hashable {
        let layout: TableLayoutKey
        let cellLocation: Int
        let isHeader: Bool
    }

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
        render(in: self)
    }

    func renderAnnotations(in textView: MarkdownTextView) {
        precondition(self.textView === textView, "annotation renderer used with another text view")
        render(in: textView)
    }

    private func render(in targetView: NSView) {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }
        precondition(
            drawingTargetView == nil,
            "annotation renderer does not support nested drawing"
        )
        drawingTargetView = targetView
        defer { drawingTargetView = nil }

        let ranges = textView.selectedRanges.compactMap { $0.rangeValue }
        let visibleRange = visibleCharacterRange(
            in: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
        drawTables(
            in: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            selectedRanges: ranges,
            visibleRange: visibleRange
        )
        drawImages(
            in: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            visibleRange: visibleRange
        )

        let tokens = MarkdownAnnotationParser.tokens(in: textView.string, selectedRanges: ranges)
        guard !tokens.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)

        var occupiedRects: [NSRect] = []
        for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
            guard token.range.location != NSNotFound,
                token.range.location < textView.string.utf16.count
            else { continue }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: token.range,
                actualCharacterRange: nil
            )
            let effectiveGlyphRange =
                glyphRange.length > 0
                ? glyphRange
                : NSRange(
                    location: min(glyphRange.location, max(0, layoutManager.numberOfGlyphs - 1)),
                    length: 1
                )
            var rect = layoutManager.boundingRect(
                forGlyphRange: effectiveGlyphRange,
                in: textContainer
            )
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            rect = textView.convert(rect, to: self)
            let drawRect = annotationRect(for: token, near: rect, occupiedRects: occupiedRects)
            occupiedRects.append(drawRect.insetBy(dx: -4, dy: -2))
            draw(token: token, in: drawRect)
        }
    }

    private func drawImages(
        in textView: MarkdownTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        visibleRange: NSRange
    ) {
        let markdown = textView.string
        let visibleImages = MarkdownImageParser.images(in: markdown, range: visibleRange)
        guard !visibleImages.isEmpty else { return }

        let excludedRanges = imageOverlayExcludedRanges(in: textView, searchRange: visibleRange)
        let images = visibleImages.filter { image in
            !excludedRanges.contains { NSIntersectionRange($0, image.range).length > 0 }
        }
        guard !images.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)
        for image in images {
            let lineRange = (textView.string as NSString).lineRange(for: image.range)
            let frame = imageFrame(
                for: lineRange,
                image: image,
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
            let resolved = textView.resolvedMarkdownImage(for: image)
            drawImageReference(image, resolved: resolved, in: frame)
        }
    }

    private func imageFrame(
        for lineRange: NSRange,
        image: MarkdownImageReference,
        textView: MarkdownTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        let theme = currentTheme
        let safeRange = NSRange(
            location: lineRange.location,
            length: max(
                1,
                min(lineRange.length, max(1, textView.string.utf16.count - lineRange.location))
            )
        )
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: safeRange,
            actualCharacterRange: nil
        )
        let glyphIndex = min(glyphRange.location, max(0, layoutManager.numberOfGlyphs - 1))
        var effectiveRange = NSRange(location: 0, length: 0)
        var lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &effectiveRange
        )
        lineRect.origin.x += textView.textContainerOrigin.x
        lineRect.origin.y += textView.textContainerOrigin.y
        lineRect = textView.convert(lineRect, to: drawingTargetView)

        let sourceRect = rect(
            for: image.range,
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
        let maxWidth = min(
            theme.scaledMetric(540, minimum: 360),
            max(120, textContainer.containerSize.width)
        )
        let maxHeight = theme.scaledMetric(300, minimum: 192)
        let resolved = textView.resolvedMarkdownImage(for: image)
        let imageSize = resolved.image?.size ?? NSSize(width: maxWidth, height: maxHeight * 0.62)
        let fitted = fittedSize(imageSize, within: NSSize(width: maxWidth, height: maxHeight))

        return NSRect(
            x: sourceRect.minX,
            y: lineRect.minY + theme.scaledMetric(10, minimum: 7),
            width: fitted.width,
            height: fitted.height
        )
    }

    private func drawImageReference(
        _ reference: MarkdownImageReference,
        resolved: MarkdownResolvedImage,
        in frame: NSRect
    ) {
        let theme = currentTheme
        let radius = theme.scaledMetric(7, minimum: 5)
        let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        if let image = resolved.image {
            image.draw(
                in: frame,
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )
        } else {
            NSColor(calibratedRed: 0.956, green: 0.962, blue: 0.966, alpha: 0.92).setFill()
            frame.fill()
            let label = placeholderLabel(for: reference, resolved: resolved)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: theme.smallFont,
                .foregroundColor: theme.secondaryTextColor,
                .kern: 0,
            ]
            let textRect = frame.insetBy(
                dx: theme.scaledMetric(13, minimum: 9),
                dy: theme.scaledMetric(11, minimum: 8)
            )
            (label as NSString).draw(in: textRect, withAttributes: attributes)
        }

        NSGraphicsContext.restoreGraphicsState()
        theme.secondaryTextColor.withAlphaComponent(0.20).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func placeholderLabel(
        for reference: MarkdownImageReference,
        resolved: MarkdownResolvedImage
    ) -> String {
        if let sourceURL = resolved.sourceURL,
            !FileManager.default.fileExists(atPath: sourceURL.path)
        {
            return "Missing image: \(resolved.displayName)"
        }

        return reference.altText.isEmpty ? resolved.displayName : reference.altText
    }

    private func fittedSize(_ source: NSSize, within maximum: NSSize) -> NSSize {
        guard source.width > 0, source.height > 0 else {
            return maximum
        }
        let scale = min(maximum.width / source.width, maximum.height / source.height, 1)
        return NSSize(
            width: max(24, floor(source.width * scale)),
            height: max(24, floor(source.height * scale))
        )
    }

    private func imageOverlayExcludedRanges(
        in textView: MarkdownTextView,
        searchRange: NSRange
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        let markdown = textView.string
        let nsString = markdown as NSString
        guard nsString.length > 0 else { return [] }

        let boundedSearchRange = NSIntersectionRange(
            searchRange,
            NSRange(location: 0, length: nsString.length)
        )
        guard boundedSearchRange.location != NSNotFound else { return [] }

        var index = nsString.lineRange(
            for: NSRange(location: boundedSearchRange.location, length: 0)
        ).location
        let searchEnd = NSMaxRange(
            nsString.lineRange(
                for: NSRange(
                    location: min(NSMaxRange(boundedSearchRange), max(0, nsString.length - 1)),
                    length: 0
                )
            )
        )
        var fenceStart: Int? = isInsideFence(at: index, in: nsString) ? index : nil

        while index < nsString.length, index < searchEnd {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let contentRange = rangeWithoutLineEnding(lineRange, in: nsString)
            let trimmed = nsString.substring(with: contentRange).trimmingCharacters(
                in: .whitespaces
            )
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let start = fenceStart {
                    ranges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
                    fenceStart = nil
                } else {
                    fenceStart = lineRange.location
                }
            }
            index = NSMaxRange(lineRange)
        }

        if let start = fenceStart {
            ranges.append(NSRange(location: start, length: nsString.length - start))
        }

        for block in textView.tableBlocksForRendering(intersecting: boundedSearchRange) {
            guard let first = block.rows.first?.lineRange,
                let last = block.rows.last?.lineRange
            else { continue }
            ranges.append(
                NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            )
        }

        return ranges
    }

    private func drawTables(
        in textView: MarkdownTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        selectedRanges: [NSRange],
        visibleRange: NSRange
    ) {
        let blocks = textView.tableBlocksForRendering(intersecting: visibleRange)
        guard !blocks.isEmpty else { return }

        if tableLayoutRevision != textView.documentRenderRevision {
            tableColumnWidths.removeAll(keepingCapacity: true)
            tableCellLines.removeAll(keepingCapacity: true)
            tableLayoutRevision = textView.documentRenderRevision
        }

        layoutManager.ensureLayout(for: textContainer)

        for block in blocks {
            draw(
                block: block,
                in: textView,
                layoutManager: layoutManager,
                textContainer: textContainer,
                selectedRanges: selectedRanges,
                visibleRange: visibleRange
            )
        }
    }

    private func draw(
        block: MarkdownTableBlock,
        in textView: MarkdownTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        selectedRanges: [NSRange],
        visibleRange: NSRange
    ) {
        let visibleRows = block.rows.filter { !$0.isSeparator }
        guard !visibleRows.isEmpty else { return }
        let theme = currentTheme
        let padding = theme.scaledMetric(14, minimum: 9)
        let font = theme.codeFont
        let headerFont = NSFont.monospacedSystemFont(
            ofSize: theme.scaledMetric(15, minimum: 10),
            weight: .semibold
        )
        let layoutKey = TableLayoutKey(
            blockLocation: block.range.location,
            containerWidth: textContainer.containerSize.width,
            viewScale: theme.viewScale
        )
        let columnWidths = resolvedColumnWidths(
            for: block,
            visibleRows: visibleRows,
            textContainer: textContainer,
            padding: padding,
            font: font,
            headerFont: headerFont
        )
        let columnCount = columnWidths.count
        let tableWidth = columnWidths.reduce(0, +)
        let visibleRowIndices = rowIndices(in: block.rows, intersecting: visibleRange)
        guard let anchorIndex = visibleRowIndices.first else { return }
        let anchorRect = rect(
            for: block.rows[anchorIndex].contentRange,
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
        let tableX = anchorRect.minX

        for index in visibleRowIndices {
            let row = block.rows[index]
            let sourceRect = rect(
                for: row.contentRange,
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
            let frame = NSRect(
                x: tableX,
                y: sourceRect.minY - theme.scaledMetric(3, minimum: 2),
                width: tableWidth,
                height: max(
                    theme.scaledMetric(30, minimum: 20),
                    sourceRect.height + theme.scaledMetric(8, minimum: 5)
                )
            )
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
                fillColor =
                    index.isMultiple(of: 2)
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
                    let drawRect = NSRect(
                        x: cellX + padding,
                        y: frame.minY + theme.scaledMetric(6, minimum: 4),
                        width: max(8, columnWidths[column] - padding * 2),
                        height: max(10, frame.height - theme.scaledMetric(10, minimum: 7))
                    )
                    let line = cachedCellLine(
                        for: cell,
                        isHeader: row.isHeader,
                        layoutKey: layoutKey,
                        font: row.isHeader ? headerFont : font,
                        color: row.isHeader
                            ? theme.textColor : theme.textColor.withAlphaComponent(0.92)
                    )
                    draw(line: line, font: row.isHeader ? headerFont : font, in: drawRect)
                }

                cellX += columnWidths[column]
            }
        }
    }

    private func resolvedColumnWidths(
        for block: MarkdownTableBlock,
        visibleRows: [MarkdownTableRow],
        textContainer: NSTextContainer,
        padding: CGFloat,
        font: NSFont,
        headerFont: NSFont
    ) -> [CGFloat] {
        let theme = currentTheme
        let key = TableLayoutKey(
            blockLocation: block.range.location,
            containerWidth: textContainer.containerSize.width,
            viewScale: theme.viewScale
        )
        if let cached = tableColumnWidths[key] {
            return cached
        }

        let columnCount = max(visibleRows.map { $0.cells.count }.max() ?? 0, 1)
        var widths = Array(
            repeating: theme.scaledMetric(88, minimum: 58),
            count: columnCount
        )
        for row in visibleRows {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: row.isHeader ? headerFont : font
            ]
            for (index, cell) in row.cells.enumerated() where index < widths.count {
                let width =
                    ceil(
                        (cell.text as NSString).size(withAttributes: attributes).width
                    ) + padding * 2
                widths[index] = max(
                    widths[index],
                    min(width, theme.scaledMetric(560, minimum: 360))
                )
            }
        }

        let maximumWidth = max(
            theme.scaledMetric(300, minimum: 220),
            textContainer.containerSize.width - theme.scaledMetric(18, minimum: 12)
        )
        let naturalWidth = widths.reduce(0, +)
        if naturalWidth > maximumWidth {
            let scale = maximumWidth / naturalWidth
            widths = widths.map {
                max(theme.scaledMetric(72, minimum: 48), floor($0 * scale))
            }
        } else if naturalWidth < maximumWidth, widths.count > 1 {
            widths[widths.count - 1] += floor(maximumWidth - naturalWidth)
        }

        tableColumnWidths[key] = widths
        return widths
    }

    private func cachedCellLine(
        for cell: MarkdownTableCell,
        isHeader: Bool,
        layoutKey: TableLayoutKey,
        font: NSFont,
        color: NSColor
    ) -> CTLine {
        let key = TableCellLineKey(
            layout: layoutKey,
            cellLocation: cell.contentRange.location,
            isHeader: isHeader
        )
        if let cached = tableCellLines[key] {
            return cached
        }

        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: renderedCellText(cell.text),
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .kern: 0,
                ]
            )
        )
        tableCellLines[key] = line
        return line
    }

    private func draw(line: CTLine, font: NSFont, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
            let drawingTargetView
        else { return }

        context.saveGState()
        context.clip(to: rect)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: drawingTargetView.bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(
            x: rect.minX,
            y: drawingTargetView.bounds.height - rect.minY - font.ascender
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func rowIndices(
        in rows: [MarkdownTableRow],
        intersecting range: NSRange
    ) -> Range<Int> {
        guard !rows.isEmpty, range.location != NSNotFound else { return 0..<0 }

        var lower = 0
        var upper = rows.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(rows[middle].lineRange) <= range.location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let first = lower
        let rangeEnd = NSMaxRange(range)
        while lower < rows.count, rows[lower].lineRange.location < rangeEnd {
            lower += 1
        }
        return first..<lower
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
            safeRange = NSRange(
                location: min(range.location, max(0, layoutManager.numberOfGlyphs - 1)),
                length: 1
            )
        }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: safeRange,
            actualCharacterRange: nil
        )
        let effectiveGlyphRange =
            glyphRange.length > 0
            ? glyphRange
            : NSRange(
                location: min(glyphRange.location, max(0, layoutManager.numberOfGlyphs - 1)),
                length: 1
            )
        var rect = layoutManager.boundingRect(forGlyphRange: effectiveGlyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return textView.convert(rect, to: drawingTargetView)
    }

    private func annotationRect(
        for token: MarkdownAnnotationToken,
        near rect: NSRect,
        occupiedRects: [NSRect]
    ) -> NSRect {
        let size = annotationSize(for: token)
        var origin: NSPoint
        let theme = currentTheme

        switch token.role {
        case .heading:
            origin = NSPoint(
                x: max(8, rect.minX - size.width - theme.scaledMetric(9, minimum: 6)),
                y: rect.minY + theme.scaledMetric(8, minimum: 5)
            )
        case .linkSource:
            origin = NSPoint(
                x: max(8, rect.minX),
                y: max(0, rect.minY - size.height - theme.scaledMetric(7, minimum: 5))
            )
        case .linkTarget:
            origin = NSPoint(
                x: rect.minX + theme.scaledMetric(2, minimum: 1),
                y: max(0, rect.minY - size.height - theme.scaledMetric(1, minimum: 1))
            )
        case .codeFence:
            origin = NSPoint(x: rect.minX, y: rect.minY)
        case .inlineDelimiter:
            origin = NSPoint(x: rect.minX, y: max(0, rect.minY - size.height + 1))
        }

        var proposed = NSRect(origin: origin, size: size)
        while occupiedRects.contains(where: { $0.intersects(proposed) }) {
            proposed.origin.y = max(
                0,
                proposed.origin.y - proposed.height - theme.scaledMetric(3, minimum: 2)
            )
        }
        return proposed
    }

    private func annotationSize(for token: MarkdownAnnotationToken) -> NSSize {
        let theme = currentTheme
        let font = annotationFont(for: token)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: 0,
        ]
        let size = (token.label as NSString).size(withAttributes: attributes)
        if token.role == .linkSource {
            return NSSize(
                width: min(
                    theme.scaledMetric(460, minimum: 300),
                    ceil(size.width) + theme.scaledMetric(12, minimum: 8)
                ),
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
            .kern: 0,
        ]

        if token.role == .linkSource || token.role == .linkTarget {
            NSColor(calibratedWhite: 1.0, alpha: 0.82).setFill()
            let radius = theme.scaledMetric(4, minimum: 2.5)
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }

        let drawRect =
            token.role == .linkSource
            ? rect.insetBy(
                dx: theme.scaledMetric(6, minimum: 4),
                dy: theme.scaledMetric(2, minimum: 1.5)
            )
            : rect
        (token.label as NSString).draw(in: drawRect, withAttributes: attributes)
    }

    private func annotationFont(for token: MarkdownAnnotationToken) -> NSFont {
        let theme = currentTheme
        switch token.role {
        case .linkSource, .linkTarget:
            return NSFont.monospacedSystemFont(
                ofSize: theme.scaledMetric(10.5, minimum: 8),
                weight: .medium
            )
        default:
            return NSFont.monospacedSystemFont(
                ofSize: theme.scaledMetric(11.5, minimum: 8.5),
                weight: .medium
            )
        }
    }

    private var currentTheme: MarkdownTheme {
        textView?.styler.theme ?? fallbackTheme
    }

    private func visibleCharacterRange(
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRange {
        let documentLength = (textView.string as NSString).length
        guard documentLength > 0 else { return NSRange(location: 0, length: 0) }

        var queryRect = textView.visibleRect.insetBy(dx: -80, dy: -120)
        queryRect.origin.x -= textView.textContainerOrigin.x
        queryRect.origin.y -= textView.textContainerOrigin.y

        let glyphRange = layoutManager.glyphRange(forBoundingRect: queryRect, in: textContainer)
        guard glyphRange.length > 0 else {
            return NSRange(location: 0, length: documentLength)
        }

        var characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        characterRange = NSIntersectionRange(
            characterRange,
            NSRange(location: 0, length: documentLength)
        )
        guard characterRange.location != NSNotFound else {
            return NSRange(location: 0, length: documentLength)
        }

        let nsString = textView.string as NSString
        let startLine = nsString.lineRange(
            for: NSRange(location: characterRange.location, length: 0)
        )
        let endLocation = min(NSMaxRange(characterRange), max(0, documentLength - 1))
        let endLine = nsString.lineRange(for: NSRange(location: endLocation, length: 0))
        return NSRange(
            location: startLine.location,
            length: NSMaxRange(endLine) - startLine.location
        )
    }

    private func isInsideFence(at location: Int, in nsString: NSString) -> Bool {
        var index = 0
        var insideFence = false
        while index < min(location, nsString.length) {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let contentRange = rangeWithoutLineEnding(lineRange, in: nsString)
            let trimmed = nsString.substring(with: contentRange).trimmingCharacters(
                in: .whitespaces
            )
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence.toggle()
            }
            index = NSMaxRange(lineRange)
        }
        return insideFence
    }

    private func renderedCellText(_ text: String) -> String {
        guard
            text.rangeOfCharacter(
                from: CharacterSet(charactersIn: "![`*_~\\")
            ) != nil
        else {
            return text
        }
        var output = text

        for (regex, template) in Self.renderedCellReplacements {
            let range = NSRange(location: 0, length: (output as NSString).length)
            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: template
            )
        }

        return output.replacingOccurrences(of: #"\\|"#, with: "|")
    }

    private static func cellRegex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("invalid table cell rendering expression: \(error)")
        }
    }

    private func rangeWithoutLineEnding(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
        var length = lineRange.length
        while length > 0 {
            let character = nsString.character(at: lineRange.location + length - 1)
            guard character == 10 || character == 13 else {
                break
            }
            length -= 1
        }
        return NSRange(location: lineRange.location, length: length)
    }
}
