import AppKit

public final class MarkdownTextView: NSTextView, NSTextFieldDelegate {
    public let styler: MarkdownStyler
    public var onContentChange: ((String) -> Void)?
    public var onSelectionChange: (() -> Void)?
    public var onViewScaleChange: (() -> Void)?
    public var markdownImageBaseURL: URL? {
        didSet {
            imageCache.removeAll()
            needsDisplay = true
        }
    }

    private let localUndoManager = UndoManager()
    private var isApplyingMarkdownStyle = false
    private var activeEditableSourceRange: NSRange?
    private var isUpdatingSourceEditor = false
    private var imageCache: [String: MarkdownResolvedImage] = [:]
    private lazy var sourceEditor: NSTextField = {
        let field = NSTextField(frame: .zero)
        field.isHidden = true
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.96)
        field.textColor = styler.theme.syntaxVisibleColor
        field.font = sourceEditorFont
        field.lineBreakMode = .byTruncatingMiddle
        field.delegate = self
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor(calibratedRed: 0.840, green: 0.858, blue: 0.878, alpha: 1).cgColor
        return field
    }()

    public init(frame frameRect: NSRect = .zero, styler: MarkdownStyler = MarkdownStyler()) {
        self.styler = styler
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(containerSize: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        super.init(frame: frameRect, textContainer: textContainer)
        configure()
        addSubview(sourceEditor)
    }

    public override var undoManager: UndoManager? {
        localUndoManager
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func loadMarkdown(_ markdown: String) {
        isApplyingMarkdownStyle = true
        textStorage?.setAttributedString(NSAttributedString(string: markdown))
        isApplyingMarkdownStyle = false
        applyMarkdownStyle()
    }

    public func loadMarkdownForPrint(_ markdown: String) {
        guard let textStorage else { return }
        isApplyingMarkdownStyle = true
        textStorage.setAttributedString(styler.attributedString(for: markdown, selectedRanges: []))
        sourceEditor.isHidden = true
        activeEditableSourceRange = nil
        isApplyingMarkdownStyle = false
    }

    public func applyMarkdownStyle() {
        guard !isApplyingMarkdownStyle, let textStorage else { return }
        let ranges = selectedRanges.compactMap { $0.rangeValue }
        isApplyingMarkdownStyle = true
        let undoWasEnabled = undoManager?.isUndoRegistrationEnabled ?? false
        if undoWasEnabled {
            undoManager?.disableUndoRegistration()
        }
        styler.apply(to: textStorage, selectedRanges: ranges)
        super.setSelectedRanges(ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        if undoWasEnabled {
            undoManager?.enableUndoRegistration()
        }
        isApplyingMarkdownStyle = false
        updateSourceEditor()
    }

    public override func didChangeText() {
        applyMarkdownStyle()
        super.didChangeText()
        onContentChange?(string)
        updateSourceEditor()
    }

    public override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        guard !isApplyingMarkdownStyle else { return }
        applyMarkdownStyle()
        enclosingScrollView?.contentView.needsDisplay = true
        updateSourceEditor()
        onSelectionChange?()
    }

    public override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        guard !isApplyingMarkdownStyle else { return }
        if !stillSelectingFlag {
            applyMarkdownStyle()
            enclosingScrollView?.contentView.needsDisplay = true
            updateSourceEditor()
            onSelectionChange?()
        }
    }

    public func wrapSelection(prefix: String, suffix: String) {
        guard let storage = textStorage else { return }
        let selected = selectedRange()
        let nsString = storage.string as NSString
        if selected.length > 0 {
            let selectedText = nsString.substring(with: selected)
            let replacement = prefix + selectedText + suffix
            if shouldChangeText(in: selected, replacementString: replacement) {
                replaceCharacters(in: selected, with: replacement)
                didChangeText()
                setSelectedRange(NSRange(location: selected.location + prefix.count, length: selected.length))
            }
        } else {
            let replacement = prefix + suffix
            if shouldChangeText(in: selected, replacementString: replacement) {
                replaceCharacters(in: selected, with: replacement)
                didChangeText()
                setSelectedRange(NSRange(location: selected.location + prefix.count, length: 0))
            }
        }
    }

    public func makeHeading(level: Int) {
        let nsString = string as NSString
        let selection = selectedRange()
        let lineRange = nsString.lineRange(for: selection)
        let line = nsString.substring(with: rangeWithoutLineEnding(lineRange, in: nsString))
        let hashes = String(repeating: "#", count: max(1, min(level, 6))) + " "
        let newLine: String

        if let match = firstHeadingMatch(in: line) {
            let body = (line as NSString).substring(from: match.length)
            newLine = hashes + body
        } else {
            newLine = hashes + line
        }

        let contentRange = rangeWithoutLineEnding(lineRange, in: nsString)
        if shouldChangeText(in: contentRange, replacementString: newLine) {
            replaceCharacters(in: contentRange, with: newLine)
            didChangeText()
            setSelectedRange(NSRange(location: min(contentRange.location + hashes.count, (string as NSString).length), length: 0))
        }
    }

    public func increaseTextSize() {
        setViewScale(styler.theme.viewScale * MarkdownTheme.zoomStep)
    }

    public func decreaseTextSize() {
        setViewScale(styler.theme.viewScale / MarkdownTheme.zoomStep)
    }

    public func resetTextSize() {
        setViewScale(MarkdownTheme.defaultViewScale)
    }

    public func setTextScale(_ scale: CGFloat) {
        setViewScale(scale)
    }

    public func setViewScale(_ scale: CGFloat) {
        let selected = selectedRange()
        styler.theme = styler.theme.withViewScale(scale)
        font = styler.theme.bodyFont
        updateSourceEditorAppearance()
        applyMarkdownStyle()
        setSelectedRange(NSRange(location: min(selected.location, (string as NSString).length), length: selected.length))
        needsLayout = true
        needsDisplay = true
        onViewScaleChange?()
    }

    public func resolvedMarkdownImage(for reference: MarkdownImageReference) -> MarkdownResolvedImage {
        let cacheKey = "\(markdownImageBaseURL?.path ?? "")|\(reference.target)"
        if let cached = imageCache[cacheKey] {
            return cached
        }

        let displayName = MarkdownImageResolver.fileURL(for: reference.target, baseURL: markdownImageBaseURL)?.lastPathComponent
            ?? reference.target
        let resolved: MarkdownResolvedImage
        if let url = MarkdownImageResolver.fileURL(for: reference.target, baseURL: markdownImageBaseURL),
           let image = NSImage(contentsOf: url) {
            resolved = MarkdownResolvedImage(image: image, displayName: displayName, sourceURL: url)
        } else {
            resolved = MarkdownResolvedImage(image: nil, displayName: displayName, sourceURL: nil)
        }
        imageCache[cacheKey] = resolved
        return resolved
    }

    private func configure() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = true
        isContinuousSpellCheckingEnabled = true
        usesAdaptiveColorMappingForDarkAppearance = true
        insertionPointColor = styler.theme.accentColor
        selectedTextAttributes = [
            .backgroundColor: styler.theme.selectionColor
        ]
        font = styler.theme.bodyFont
        textColor = styler.theme.textColor
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = NSSize(width: styler.theme.scaledMetric(28), height: styler.theme.scaledMetric(72))
        textContainer?.lineFragmentPadding = 0
    }

    private func updateSourceEditor() {
        guard !isApplyingMarkdownStyle, !isUpdatingSourceEditor else { return }
        if let window, window.firstResponder === sourceEditor.currentEditor() {
            return
        }

        let selection = selectedRange()
        guard selection.length == 0,
              let span = MarkdownSourceSpanParser.editableSpan(containing: selection.location, in: string),
              let layoutManager,
              let textContainer
        else {
            sourceEditor.isHidden = true
            activeEditableSourceRange = nil
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
        let effectiveGlyphRange = glyphRange.length > 0 ? glyphRange : NSRange(location: min(glyphRange.location, max(0, layoutManager.numberOfGlyphs - 1)), length: 1)
        var rect = layoutManager.boundingRect(forGlyphRange: effectiveGlyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let attributes: [NSAttributedString.Key: Any] = [
            .font: sourceEditor.font ?? sourceEditorFont
        ]
        let sourceSize = (span.source as NSString).size(withAttributes: attributes)
        let width = min(
            max(styler.theme.scaledMetric(170, minimum: 122), ceil(sourceSize.width) + styler.theme.scaledMetric(18, minimum: 12)),
            max(styler.theme.scaledMetric(240, minimum: 170), bounds.width - rect.minX - styler.theme.scaledMetric(26, minimum: 18))
        )
        let height: CGFloat = styler.theme.scaledMetric(23, minimum: 17)

        isUpdatingSourceEditor = true
        activeEditableSourceRange = span.range
        sourceEditor.stringValue = span.source
        sourceEditor.removeFromSuperview()
        addSubview(sourceEditor, positioned: .above, relativeTo: nil)
        sourceEditor.frame = NSRect(
            x: rect.minX,
            y: max(0, rect.minY - height - styler.theme.scaledMetric(4, minimum: 3)),
            width: width,
            height: height
        )
        sourceEditor.isHidden = false
        isUpdatingSourceEditor = false
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitSourceEditorIfNeeded()
    }

    public override func doCommand(by selector: Selector) {
        if window?.firstResponder === sourceEditor.currentEditor(),
           selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                commitSourceEditorIfNeeded()
            } else {
                sourceEditor.isHidden = true
                window?.makeFirstResponder(self)
            }
            return
        }
        super.doCommand(by: selector)
    }

    private func commitSourceEditorIfNeeded() {
        guard let range = activeEditableSourceRange, !sourceEditor.isHidden else { return }
        let replacement = sourceEditor.stringValue
        sourceEditor.isHidden = true
        activeEditableSourceRange = nil

        guard replacement != (string as NSString).substring(with: range) else {
            window?.makeFirstResponder(self)
            return
        }

        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: min(range.location + replacement.utf16.count, (string as NSString).length), length: 0))
        }
        window?.makeFirstResponder(self)
    }

    private func updateSourceEditorAppearance() {
        sourceEditor.textColor = styler.theme.syntaxVisibleColor
        sourceEditor.font = sourceEditorFont
        sourceEditor.layer?.cornerRadius = styler.theme.scaledMetric(5, minimum: 3.5)
    }

    private var sourceEditorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: styler.theme.scaledMetric(11.5, minimum: 8.5), weight: .medium)
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

    private func firstHeadingMatch(in line: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#) else { return nil }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, range: range)?.range
    }
}
