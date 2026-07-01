import AppKit

public final class EditorWorkspaceView: NSView {
    public let textView: MarkdownTextView
    public let scrollView: NSScrollView
    public var documentFormat: MarkdownDocumentFormat {
        didSet {
            guard oldValue != documentFormat else { return }
            documentFormat.store()
            syncFormatControl()
            updateTextInsets()
            needsLayout = true
            needsDisplay = true
            onDocumentFormatChange?(documentFormat)
        }
    }
    public var onDocumentFormatChange: ((MarkdownDocumentFormat) -> Void)?

    private let theme: MarkdownTheme
    private let annotationOverlay: MarkdownAnnotationOverlayView
    private let minimapView: MarkdownMinimapView
    private let topBarBackdropView = ChromeBackdropView(
        material: .headerView,
        tintColor: NSColor(calibratedWhite: 1.0, alpha: 0.58),
        strokeColor: NSColor(calibratedWhite: 0.72, alpha: 0.12)
    )
    private let minimapBackdropView = ChromeBackdropView(
        material: .popover,
        tintColor: NSColor(calibratedWhite: 1.0, alpha: 0.48),
        strokeColor: NSColor(calibratedRed: 0.055, green: 0.390, blue: 0.680, alpha: 0.12),
        cornerRadius: 7
    )
    private let titleLabel = NSTextField(labelWithString: "Untitled")
    private let statusLabel = NSTextField(labelWithString: "")
    private let formatLabel = NSTextField(labelWithString: "Format")
    private let formatButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rule = NSBox()
    private let formatBackdropView = ChromeBackdropView(
        material: .popover,
        tintColor: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        strokeColor: NSColor(calibratedWhite: 0.72, alpha: 0.16),
        cornerRadius: 8
    )
    private var topBarHeightConstraint: NSLayoutConstraint?
    private var minimapTrailingConstraint: NSLayoutConstraint?
    private var minimapTopConstraint: NSLayoutConstraint?
    private var minimapBottomConstraint: NSLayoutConstraint?
    private var minimapWidthConstraint: NSLayoutConstraint?
    private var titleTopConstraint: NSLayoutConstraint?
    private var statusTrailingConstraint: NSLayoutConstraint?
    private var statusBottomConstraint: NSLayoutConstraint?
    private var statusWidthConstraint: NSLayoutConstraint?
    private var ruleTopConstraint: NSLayoutConstraint?
    private var formatBottomConstraint: NSLayoutConstraint?
    private var lastTextGeometry: TextGeometry?
    private let geometryEpsilon: CGFloat = 0.25

    public init(frame frameRect: NSRect = .zero, theme: MarkdownTheme = .clean) {
        self.theme = theme
        self.textView = MarkdownTextView(styler: MarkdownStyler(theme: theme))
        self.scrollView = NSScrollView(frame: .zero)
        self.annotationOverlay = MarkdownAnnotationOverlayView(textView: textView, theme: theme)
        self.minimapView = MarkdownMinimapView(textView: textView, theme: theme)
        self.documentFormat = MarkdownDocumentFormat.stored()
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func loadMarkdown(_ markdown: String) {
        textView.loadMarkdown(markdown)
        updateMetrics()
    }

    public func setDocumentURL(_ url: URL?) {
        textView.markdownImageBaseURL = url?.deletingLastPathComponent()
        annotationOverlay.needsDisplay = true
    }

    public func updateDocumentTitle(url: URL?, isEdited: Bool) {
        let base = url?.lastPathComponent ?? "Untitled"
        titleLabel.stringValue = isEdited ? "\(base) *" : base
    }

    public func updateMetrics() {
        let text = textView.string
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let lines = max(1, text.components(separatedBy: .newlines).count)
        statusLabel.stringValue = "\(words) words  \(lines) lines"
    }

    var minimapForTesting: MarkdownMinimapView {
        minimapView
    }

    public var resolvedTextContainerWidthForTesting: CGFloat {
        textView.textContainer?.containerSize.width ?? 0
    }

    public override func layout() {
        super.layout()
        updateScaledChrome()
        updateTextInsets(preserveVisibleOrigin: true)
    }

    public override func draw(_ dirtyRect: NSRect) {
        theme.backgroundColor.setFill()
        dirtyRect.fill()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = theme.backgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 1400)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        annotationOverlay.frame = textView.bounds
        annotationOverlay.autoresizingMask = [.width, .height]
        textView.addSubview(annotationOverlay)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = theme.smallFont
        titleLabel.textColor = theme.secondaryTextColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = theme.smallFont
        statusLabel.textColor = theme.secondaryTextColor
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingTail

        formatBackdropView.translatesAutoresizingMaskIntoConstraints = false
        formatLabel.translatesAutoresizingMaskIntoConstraints = false
        formatLabel.font = theme.smallFont
        formatLabel.textColor = theme.secondaryTextColor
        formatLabel.alignment = .left

        formatButton.translatesAutoresizingMaskIntoConstraints = false
        formatButton.controlSize = .small
        formatButton.font = theme.smallFont
        formatButton.isBordered = false
        formatButton.target = self
        formatButton.action = #selector(formatSelectionChanged)
        for format in MarkdownDocumentFormat.allCases {
            formatButton.addItem(withTitle: format.menuTitle)
            formatButton.lastItem?.representedObject = format.rawValue
        }

        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.boxType = .separator
        rule.alphaValue = 0.45
        topBarBackdropView.translatesAutoresizingMaskIntoConstraints = false
        minimapBackdropView.translatesAutoresizingMaskIntoConstraints = false
        minimapView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(topBarBackdropView)
        addSubview(minimapBackdropView)
        addSubview(minimapView)
        addSubview(titleLabel)
        addSubview(statusLabel)
        addSubview(formatBackdropView)
        addSubview(formatLabel)
        addSubview(formatButton)
        addSubview(rule)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        topBarHeightConstraint = topBarBackdropView.heightAnchor.constraint(equalToConstant: 54)
        minimapTrailingConstraint = minimapView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        minimapTopConstraint = minimapView.topAnchor.constraint(equalTo: topAnchor, constant: 58)
        minimapBottomConstraint = minimapView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40)
        minimapWidthConstraint = minimapView.widthAnchor.constraint(equalToConstant: 86)
        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13)
        statusTrailingConstraint = statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)
        statusBottomConstraint = statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        statusWidthConstraint = statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ruleTopConstraint = rule.topAnchor.constraint(equalTo: topAnchor, constant: 44)
        formatBottomConstraint = formatBackdropView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            topBarBackdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBarBackdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBarBackdropView.topAnchor.constraint(equalTo: topAnchor),
            topBarHeightConstraint!,

            minimapTrailingConstraint!,
            minimapTopConstraint!,
            minimapBottomConstraint!,
            minimapWidthConstraint!,

            minimapBackdropView.leadingAnchor.constraint(equalTo: minimapView.leadingAnchor),
            minimapBackdropView.trailingAnchor.constraint(equalTo: minimapView.trailingAnchor),
            minimapBackdropView.topAnchor.constraint(equalTo: minimapView.topAnchor),
            minimapBackdropView.bottomAnchor.constraint(equalTo: minimapView.bottomAnchor),

            titleTopConstraint!,
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.42),

            statusTrailingConstraint!,
            statusBottomConstraint!,
            statusWidthConstraint!,

            formatBackdropView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            formatBottomConstraint!,
            formatBackdropView.heightAnchor.constraint(equalToConstant: 32),

            formatLabel.leadingAnchor.constraint(equalTo: formatBackdropView.leadingAnchor, constant: 11),
            formatLabel.centerYAnchor.constraint(equalTo: formatBackdropView.centerYAnchor),

            formatButton.leadingAnchor.constraint(equalTo: formatLabel.trailingAnchor, constant: 7),
            formatButton.trailingAnchor.constraint(equalTo: formatBackdropView.trailingAnchor, constant: -4),
            formatButton.centerYAnchor.constraint(equalTo: formatBackdropView.centerYAnchor),
            formatButton.widthAnchor.constraint(equalToConstant: 118),

            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            ruleTopConstraint!,
            rule.heightAnchor.constraint(equalToConstant: 1)
        ])

        textView.onViewScaleChange = { [weak self] in
            guard let self else { return }
            self.updateScaledChrome()
            self.updateTextInsets()
            self.needsLayout = true
            self.needsDisplay = true
        }
        updateScaledChrome()
        syncFormatControl()
    }

    @objc private func boundsDidChange() {
        updateTextInsets(preserveVisibleOrigin: true)
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    @objc private func textDidChange() {
        updateTextInsets(preserveVisibleOrigin: true)
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    @objc private func selectionDidChange() {
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    private func updateTextInsets(preserveVisibleOrigin: Bool = false) {
        let visibleWidth = max(320, scrollView.contentSize.width)
        let scale = currentTheme.viewScale
        let horizontalPadding = documentFormat.editorHorizontalPadding(scale: scale)
        let centeredInset = (visibleWidth - documentFormat.editorContentWidth) / 2
        let sideInset = max(horizontalPadding, centeredInset)
        let verticalInset = documentFormat.editorVerticalInset(scale: scale)
        let containerWidth = max(240, visibleWidth - (sideInset * 2))
        let geometry = TextGeometry(
            visibleWidth: visibleWidth,
            sideInset: sideInset,
            verticalInset: verticalInset,
            containerWidth: containerWidth
        )

        if lastTextGeometry?.matches(geometry, epsilon: geometryEpsilon) != true {
            let newInset = NSSize(width: sideInset, height: verticalInset)
            if !sizesMatch(textView.textContainerInset, newInset) {
                textView.textContainerInset = newInset
            }

            if let textContainer = textView.textContainer {
                let newContainerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
                if !sizesMatch(textContainer.containerSize, newContainerSize) {
                    textContainer.containerSize = newContainerSize
                }
                if textContainer.widthTracksTextView {
                    textContainer.widthTracksTextView = false
                }
            }

            if abs(textView.frame.size.width - visibleWidth) > geometryEpsilon {
                textView.frame.size.width = visibleWidth
            }
            lastTextGeometry = geometry
        }

        updateDocumentHeight(preserveVisibleOrigin: preserveVisibleOrigin)
        if annotationOverlay.frame != textView.bounds {
            annotationOverlay.frame = textView.bounds
        }
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    private func updateDocumentHeight(preserveVisibleOrigin: Bool) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let clipView = scrollView.contentView
        let originalOrigin = clipView.bounds.origin

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let laidOutHeight = roundedUpToDevicePixel(textView.textContainerOrigin.y + usedRect.maxY + textView.textContainerInset.height)
        let documentHeight = max(scrollView.contentSize.height, laidOutHeight)
        if abs(textView.frame.size.height - documentHeight) > geometryEpsilon {
            textView.frame.size.height = documentHeight
        }

        guard preserveVisibleOrigin else { return }
        let maxY = max(0, textView.frame.height - clipView.bounds.height)
        let targetY = min(max(0, originalOrigin.y), maxY)
        let target = NSPoint(x: originalOrigin.x, y: targetY)
        if abs(clipView.bounds.origin.y - target.y) > geometryEpsilon ||
            abs(clipView.bounds.origin.x - target.x) > geometryEpsilon {
            clipView.scroll(to: target)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    private func updateScaledChrome() {
        let theme = currentTheme
        titleLabel.font = theme.smallFont
        statusLabel.font = theme.smallFont
        formatLabel.font = theme.smallFont
        formatButton.font = theme.smallFont
        titleLabel.textColor = theme.secondaryTextColor
        statusLabel.textColor = theme.secondaryTextColor
        formatLabel.textColor = theme.secondaryTextColor

        minimapTrailingConstraint?.constant = -max(9, theme.scaledMetric(12))
        minimapTopConstraint?.constant = max(46, theme.scaledMetric(58))
        minimapBottomConstraint?.constant = -max(30, theme.scaledMetric(40))
        minimapWidthConstraint?.constant = max(70, theme.scaledMetric(86))
        topBarHeightConstraint?.constant = max(46, theme.scaledMetric(56))
        minimapBackdropView.cornerRadius = max(5, theme.scaledMetric(7))
        titleTopConstraint?.constant = max(10, theme.scaledMetric(13))
        statusTrailingConstraint?.constant = -max(13, theme.scaledMetric(18))
        statusBottomConstraint?.constant = -max(9, theme.scaledMetric(12))
        statusWidthConstraint?.constant = max(170, theme.scaledMetric(220))
        formatBottomConstraint?.constant = -max(9, theme.scaledMetric(12))
        ruleTopConstraint?.constant = max(38, theme.scaledMetric(44))
    }

    private func syncFormatControl() {
        for index in 0..<formatButton.numberOfItems {
            guard
                let rawValue = formatButton.item(at: index)?.representedObject as? String,
                rawValue == documentFormat.rawValue
            else {
                continue
            }
            formatButton.selectItem(at: index)
            return
        }
    }

    @objc private func formatSelectionChanged() {
        guard
            let rawValue = formatButton.selectedItem?.representedObject as? String,
            let format = MarkdownDocumentFormat(rawValue: rawValue)
        else {
            return
        }
        documentFormat = format
    }

    private var currentTheme: MarkdownTheme {
        textView.styler.theme
    }

    private func roundedUpToDevicePixel(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return (value * scale).rounded(.up) / scale
    }

    private func sizesMatch(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) <= geometryEpsilon && abs(lhs.height - rhs.height) <= geometryEpsilon
    }

    private struct TextGeometry {
        let visibleWidth: CGFloat
        let sideInset: CGFloat
        let verticalInset: CGFloat
        let containerWidth: CGFloat

        func matches(_ other: TextGeometry, epsilon: CGFloat) -> Bool {
            abs(visibleWidth - other.visibleWidth) <= epsilon &&
                abs(sideInset - other.sideInset) <= epsilon &&
                abs(verticalInset - other.verticalInset) <= epsilon &&
                abs(containerWidth - other.containerWidth) <= epsilon
        }
    }
}

private final class ChromeBackdropView: NSView {
    private let materialView = NSVisualEffectView()
    private let tintView: BackdropTintView

    var cornerRadius: CGFloat {
        didSet {
            applyCornerRadius()
        }
    }

    init(
        material: NSVisualEffectView.Material,
        tintColor: NSColor,
        strokeColor: NSColor,
        cornerRadius: CGFloat = 0
    ) {
        self.tintView = BackdropTintView(fillColor: tintColor, strokeColor: strokeColor, cornerRadius: cornerRadius)
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)

        materialView.material = material
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.isEmphasized = false

        tintView.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.masksToBounds = true

        addSubview(materialView)
        addSubview(tintView)
        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func applyCornerRadius() {
        layer?.cornerRadius = cornerRadius
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = cornerRadius
        materialView.layer?.masksToBounds = true
        tintView.cornerRadius = cornerRadius
    }
}

private final class BackdropTintView: NSView {
    var fillColor: NSColor {
        didSet {
            needsDisplay = true
        }
    }

    var strokeColor: NSColor {
        didSet {
            needsDisplay = true
        }
    }

    var cornerRadius: CGFloat {
        didSet {
            needsDisplay = true
        }
    }

    init(fillColor: NSColor, strokeColor: NSColor, cornerRadius: CGFloat) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let path: NSBezierPath
        if cornerRadius > 0 {
            path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        } else {
            path = NSBezierPath(rect: bounds)
        }
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
