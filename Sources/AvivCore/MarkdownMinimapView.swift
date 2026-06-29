import AppKit

public final class MarkdownMinimapView: NSView {
    public weak var textView: MarkdownTextView?
    private let fallbackTheme: MarkdownTheme
    private var activeThumbDragOffset: CGFloat?

    public init(textView: MarkdownTextView, theme: MarkdownTheme = .clean) {
        self.textView = textView
        self.fallbackTheme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.scaledMetric(7, minimum: 5)
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        guard let textView, let metrics = viewportMetrics() else { return }
        let theme = currentTheme
        layer?.cornerRadius = theme.scaledMetric(7, minimum: 5)

        NSColor(calibratedWhite: 1.0, alpha: 0.34).setFill()
        let radius = theme.scaledMetric(7, minimum: 5)
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        NSColor(calibratedRed: 0.055, green: 0.390, blue: 0.680, alpha: 0.08).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()

        let insetX = theme.scaledMetric(7, minimum: 5)
        let maxLineWidth = max(8, bounds.width - insetX * 2)
        let lines = MarkdownMinimapStructure.lines(in: textView.string)
        let lineRanges = sourceLineRanges(in: textView.string)

        for (index, line) in lines.enumerated() where index < lineRanges.count {
            let fragments = visualLineFragments(forCharacterRange: lineRanges[index], in: textView)
            for fragment in fragments {
                let y = metrics.projectedY(forDocumentY: fragment.minY)
                guard y >= bounds.minY - 1, y <= bounds.maxY + 1 else { continue }
                let lineStep = max(1.2, metrics.projectedHeight(forDocumentHeight: fragment.height))
                draw(line, at: y, lineStep: lineStep, insetX: insetX, maxLineWidth: maxLineWidth)
            }
        }

        if let selected = selectedLineMarker(in: textView, metrics: metrics) {
            drawSelectionMarker(at: selected.y, lineStep: selected.lineStep)
        }

        drawViewportThumb(metrics)
    }

    public override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        guard let metrics = viewportMetrics() else { return }
        if metrics.thumbRect.contains(NSPoint(x: metrics.thumbRect.midX, y: y)) {
            activeThumbDragOffset = y - metrics.thumbRect.minY
            scrollTextView(toThumbMinY: y - (activeThumbDragOffset ?? 0), metrics: metrics)
        } else {
            activeThumbDragOffset = metrics.thumbRect.height / 2
            scrollTextView(centeredAt: y, metrics: metrics)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        guard let metrics = viewportMetrics() else { return }
        if let offset = activeThumbDragOffset {
            scrollTextView(toThumbMinY: y - offset, metrics: metrics)
        } else {
            scrollTextView(centeredAt: y, metrics: metrics)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        activeThumbDragOffset = nil
    }

    public func viewportMetrics() -> MarkdownMinimapViewportMetrics? {
        guard let textView, let clipView = textView.enclosingScrollView?.contentView else { return nil }
        return viewportMetrics(for: textView, clipView: clipView)
    }

    func scrollForTesting(centeredAtMinimapY y: CGFloat) {
        guard let metrics = viewportMetrics() else { return }
        scrollTextView(centeredAt: y, metrics: metrics)
    }

    func scrollForTesting(thumbMinY y: CGFloat) {
        guard let metrics = viewportMetrics() else { return }
        scrollTextView(toThumbMinY: y, metrics: metrics)
    }

    private func drawViewportThumb(_ metrics: MarkdownMinimapViewportMetrics) {
        let theme = currentTheme

        NSColor(calibratedRed: 0.055, green: 0.390, blue: 0.680, alpha: 0.12).setFill()
        let radius = theme.scaledMetric(5, minimum: 3.5)
        NSBezierPath(roundedRect: metrics.thumbRect, xRadius: radius, yRadius: radius).fill()
        theme.accentColor.withAlphaComponent(0.18).setStroke()
        NSBezierPath(roundedRect: metrics.thumbRect, xRadius: radius, yRadius: radius).stroke()
    }

    private func draw(
        _ line: MarkdownMinimapLine,
        at y: CGFloat,
        lineStep: CGFloat,
        insetX: CGFloat,
        maxLineWidth: CGFloat
    ) {
        guard line.kind != .blank else { return }
        let theme = currentTheme

        let markerLaneWidth = theme.scaledMetric(13, minimum: 10)
        let quoteOffset = CGFloat(min(5, line.quoteDepth)) * theme.scaledMetric(2.5, minimum: 1.8)
        let contentX = insetX + markerLaneWidth + quoteOffset
        let contentWidth = max(8, maxLineWidth - markerLaneWidth - quoteOffset)
        let density = CGFloat(min(max(line.textLength, 8), 96)) / 96
        let baseWidth = max(8, contentWidth * density)

        if line.quoteDepth > 0 {
            drawQuoteRails(depth: line.quoteDepth, y: y, lineStep: lineStep, insetX: insetX)
        }

        switch line.kind {
        case .blank:
            break
        case .heading(let level):
            let height = min(3.2, max(1.6, lineStep * 0.74))
            let widthBoost = CGFloat(max(0, 6 - level)) * theme.scaledMetric(3, minimum: 2)
            drawMarkerBar(
                rect: NSRect(x: insetX + 1, y: y, width: max(3, 6 - CGFloat(level) * 0.55), height: height),
                color: theme.accentColor.withAlphaComponent(level == 1 ? 0.78 : 0.62)
            )
            drawMarkerBar(
                rect: NSRect(x: contentX, y: y, width: min(contentWidth, baseWidth + widthBoost), height: height),
                color: theme.accentColor.withAlphaComponent(level == 1 ? 0.66 : 0.52)
            )
        case .unorderedList(let depth):
            drawListGlyph(checked: nil, ordered: false, depth: depth, y: y, lineStep: lineStep, insetX: insetX)
            drawContentStroke(x: contentX + CGFloat(depth) * 2.5, y: y, width: baseWidth, lineStep: lineStep, color: theme.secondaryTextColor.withAlphaComponent(0.34))
        case .orderedList(let depth):
            drawListGlyph(checked: nil, ordered: true, depth: depth, y: y, lineStep: lineStep, insetX: insetX)
            drawContentStroke(x: contentX + CGFloat(depth) * 2.5, y: y, width: baseWidth, lineStep: lineStep, color: theme.secondaryTextColor.withAlphaComponent(0.34))
        case .taskList(let checked, let depth):
            drawListGlyph(checked: checked, ordered: false, depth: depth, y: y, lineStep: lineStep, insetX: insetX)
            drawContentStroke(x: contentX + CGFloat(depth) * 2.5, y: y, width: baseWidth, lineStep: lineStep, color: taskColor(checked: checked).withAlphaComponent(0.43))
        case .quote:
            drawContentStroke(x: contentX, y: y, width: baseWidth, lineStep: lineStep, color: theme.quoteBarColor.withAlphaComponent(0.34))
        case .tableHeader(let columns):
            drawTableRow(columns: columns, x: contentX - 1, y: y, width: max(baseWidth, contentWidth * 0.72), lineStep: lineStep, alpha: 0.58)
        case .tableSeparator(let columns):
            drawTableRow(columns: columns, x: contentX - 1, y: y, width: max(baseWidth, contentWidth * 0.72), lineStep: lineStep, alpha: 0.26)
        case .tableRow(let columns):
            drawTableRow(columns: columns, x: contentX - 1, y: y, width: max(baseWidth, contentWidth * 0.68), lineStep: lineStep, alpha: 0.42)
        case .codeFence:
            drawCodeFence(x: insetX + 2, y: y, lineStep: lineStep)
            drawContentStroke(x: contentX, y: y, width: min(contentWidth * 0.56, max(baseWidth, 18)), lineStep: lineStep, color: codeColor.withAlphaComponent(0.48))
        case .code:
            drawCodeLine(x: contentX, y: y, width: min(contentWidth * 0.82, max(baseWidth, 22)), lineStep: lineStep)
        case .thematicBreak:
            drawContentStroke(x: contentX, y: y, width: contentWidth * 0.62, lineStep: lineStep, color: theme.syntaxVisibleColor.withAlphaComponent(0.42))
        case .body:
            drawContentStroke(x: contentX, y: y, width: baseWidth, lineStep: lineStep, color: theme.textColor.withAlphaComponent(0.22))
        }
    }

    private func drawQuoteRails(depth: Int, y: CGFloat, lineStep: CGFloat, insetX: CGFloat) {
        let theme = currentTheme
        let height = min(7, max(2.6, lineStep * 0.66))
        for quoteIndex in 0..<min(depth, 3) {
            let x = insetX + CGFloat(quoteIndex) * theme.scaledMetric(3.2, minimum: 2.4)
            drawMarkerBar(
                rect: NSRect(x: x, y: y - height * 0.15, width: theme.scaledMetric(1.6, minimum: 1.1), height: height),
                color: theme.quoteBarColor.withAlphaComponent(0.50 - CGFloat(quoteIndex) * 0.08)
            )
        }
    }

    private func drawListGlyph(
        checked: Bool?,
        ordered: Bool,
        depth: Int,
        y: CGFloat,
        lineStep: CGFloat,
        insetX: CGFloat
    ) {
        let theme = currentTheme
        let size = min(5.4, max(3.0, lineStep * 0.56))
        let x = insetX + theme.scaledMetric(2, minimum: 1.5) + CGFloat(min(depth, 5)) * theme.scaledMetric(2.8, minimum: 2)
        let rect = NSRect(x: x, y: y - size * 0.22, width: size, height: size)

        if let checked {
            let color = taskColor(checked: checked)
            color.withAlphaComponent(0.52).setStroke()
            let box = NSBezierPath(roundedRect: rect, xRadius: 1.4, yRadius: 1.4)
            box.lineWidth = 1
            box.stroke()
            if checked {
                color.withAlphaComponent(0.56).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1.3, dy: 1.3), xRadius: 0.8, yRadius: 0.8).fill()
            }
            return
        }

        if ordered {
            theme.secondaryTextColor.withAlphaComponent(0.43).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.25, dy: 0), xRadius: size * 0.18, yRadius: size * 0.18).fill()
        } else {
            theme.secondaryTextColor.withAlphaComponent(0.48).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.14, dy: size * 0.14)).fill()
        }
    }

    private func drawTableRow(columns: Int, x: CGFloat, y: CGFloat, width: CGFloat, lineStep: CGFloat, alpha: CGFloat) {
        let height = min(3.0, max(1.35, lineStep * 0.52))
        let columnCount = max(1, min(columns, 5))
        let gap: CGFloat = columnCount > 1 ? 1.3 : 0
        let cellWidth = max(2, (width - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount))
        let color = tableColor.withAlphaComponent(alpha)

        for index in 0..<columnCount {
            let cellX = x + CGFloat(index) * (cellWidth + gap)
            drawMarkerBar(
                rect: NSRect(x: cellX, y: y, width: cellWidth, height: height),
                color: color
            )
        }
    }

    private func drawCodeFence(x: CGFloat, y: CGFloat, lineStep: CGFloat) {
        let height = min(4.6, max(2.4, lineStep * 0.58))
        let color = codeColor.withAlphaComponent(0.44)
        drawMarkerBar(rect: NSRect(x: x, y: y, width: 4.2, height: 1.2), color: color)
        drawMarkerBar(rect: NSRect(x: x, y: y + height - 1.2, width: 4.2, height: 1.2), color: color)
    }

    private func drawCodeLine(x: CGFloat, y: CGFloat, width: CGFloat, lineStep: CGFloat) {
        let height = min(2.4, max(1.1, lineStep * 0.44))
        let segmentWidth = max(4, width / 4.8)
        let gap: CGFloat = 2
        let color = codeColor.withAlphaComponent(0.35)
        var currentX = x

        for index in 0..<3 {
            let multiplier: CGFloat = index == 1 ? 0.72 : (index == 2 ? 0.46 : 1)
            drawMarkerBar(
                rect: NSRect(x: currentX, y: y, width: segmentWidth * multiplier, height: height),
                color: color
            )
            currentX += segmentWidth * multiplier + gap
        }
    }

    private func drawContentStroke(x: CGFloat, y: CGFloat, width: CGFloat, lineStep: CGFloat, color: NSColor) {
        let height = min(1.8, max(0.9, lineStep * 0.48))
        drawMarkerBar(rect: NSRect(x: x, y: y, width: width, height: height), color: color)
    }

    private func drawSelectionMarker(at y: CGFloat, lineStep: CGFloat) {
        let theme = currentTheme
        let size = min(5.5, max(3.4, lineStep * 0.62))
        let rect = NSRect(x: bounds.maxX - size - theme.scaledMetric(4.5, minimum: 3), y: y - size * 0.20, width: size, height: size)
        theme.accentColor.withAlphaComponent(0.62).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func drawMarkerBar(rect: NSRect, color: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        color.setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: min(rect.height / 2, 2.2),
            yRadius: min(rect.height / 2, 2.2)
        ).fill()
    }

    private func scrollTextView(centeredAt y: CGFloat, metrics: MarkdownMinimapViewportMetrics) {
        scrollTextView(toDocumentOffset: metrics.documentOffset(centeredAtTrackY: y))
    }

    private func scrollTextView(toThumbMinY y: CGFloat, metrics: MarkdownMinimapViewportMetrics) {
        scrollTextView(toDocumentOffset: metrics.documentOffset(forThumbMinY: y))
    }

    private func scrollTextView(toDocumentOffset targetY: CGFloat) {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        needsDisplay = true
    }

    private func viewportMetrics(for textView: NSTextView, clipView: NSClipView) -> MarkdownMinimapViewportMetrics? {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let laidOutHeight = ceil(textView.textContainerOrigin.y + usedRect.maxY + textView.textContainerInset.height)
        let documentHeight = max(clipView.bounds.height, textView.bounds.height, textView.frame.height, laidOutHeight)
        let thumbInset = currentTheme.scaledMetric(3, minimum: 2)
        return MarkdownMinimapViewport.metrics(
            trackBounds: bounds,
            documentHeight: documentHeight,
            visibleRect: clipView.documentVisibleRect,
            horizontalInset: thumbInset,
            minimumThumbHeight: max(1.5, backingScaleAdjustedPixel)
        )
    }

    private func visualLineFragments(forCharacterRange range: NSRange, in textView: NSTextView) -> [NSRect] {
        guard
            range.length > 0,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return [] }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return [] }

        var fragments: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragmentGlyphRange, _ in
            guard NSIntersectionRange(fragmentGlyphRange, glyphRange).length > 0 else { return }
            var rect = usedRect
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            fragments.append(rect)
        }
        return fragments
    }

    private func selectedLineMarker(
        in textView: NSTextView,
        metrics: MarkdownMinimapViewportMetrics
    ) -> (y: CGFloat, lineStep: CGFloat)? {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        let stringLength = (textView.string as NSString).length
        guard stringLength > 0 else { return nil }

        layoutManager.ensureLayout(for: textContainer)
        let location = min(max(0, textView.selectedRange().location), stringLength - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        var rect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return (
            y: metrics.projectedY(forDocumentY: rect.minY),
            lineStep: max(1.2, metrics.projectedHeight(forDocumentHeight: rect.height))
        )
    }

    private func sourceLineRanges(in text: String) -> [NSRange] {
        let nsString = text as NSString
        guard nsString.length > 0 else { return [NSRange(location: 0, length: 0)] }

        var ranges: [NSRange] = []
        var start = 0
        while start <= nsString.length {
            var end = start
            while end < nsString.length {
                let character = nsString.character(at: end)
                if character == 10 || character == 13 {
                    break
                }
                end += 1
            }
            ranges.append(NSRange(location: start, length: end - start))

            if end >= nsString.length {
                break
            }
            let newlineCharacter = nsString.character(at: end)
            end += 1
            if newlineCharacter == 13, end < nsString.length, nsString.character(at: end) == 10 {
                end += 1
            }
            start = end
            if start == nsString.length {
                ranges.append(NSRange(location: start, length: 0))
                break
            }
        }
        return ranges
    }

    private var backingScaleAdjustedPixel: CGFloat {
        1 / max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }

    private var tableColor: NSColor {
        NSColor(calibratedRed: 0.780, green: 0.430, blue: 0.125, alpha: 1.0)
    }

    private var codeColor: NSColor {
        NSColor(calibratedRed: 0.230, green: 0.280, blue: 0.345, alpha: 1.0)
    }

    private func taskColor(checked: Bool) -> NSColor {
        checked
            ? NSColor(calibratedRed: 0.075, green: 0.455, blue: 0.385, alpha: 1.0)
            : currentTheme.accentColor
    }

    private var currentTheme: MarkdownTheme {
        textView?.styler.theme ?? fallbackTheme
    }
}
