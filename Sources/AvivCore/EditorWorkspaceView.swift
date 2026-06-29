import AppKit

public final class EditorWorkspaceView: NSView {
    public let textView: MarkdownTextView
    public let scrollView: NSScrollView

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
    private let rule = NSBox()
    private let maxColumnWidth: CGFloat = 860
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

    public init(frame frameRect: NSRect = .zero, theme: MarkdownTheme = .clean) {
        self.theme = theme
        self.textView = MarkdownTextView(styler: MarkdownStyler(theme: theme))
        self.scrollView = NSScrollView(frame: .zero)
        self.annotationOverlay = MarkdownAnnotationOverlayView(textView: textView, theme: theme)
        self.minimapView = MarkdownMinimapView(textView: textView, theme: theme)
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

    public override func layout() {
        super.layout()
        updateScaledChrome()
        updateTextInsets()
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
    }

    @objc private func boundsDidChange() {
        updateTextInsets()
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    @objc private func textDidChange() {
        updateTextInsets()
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    @objc private func selectionDidChange() {
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    private func updateTextInsets() {
        let visibleWidth = max(320, scrollView.contentSize.width)
        let scale = currentTheme.viewScale
        let horizontalPadding = max(CGFloat(20), 28 * scale)
        let sideInset = max(horizontalPadding, ((visibleWidth - maxColumnWidth) / 2) + horizontalPadding)
        textView.textContainerInset = NSSize(width: sideInset, height: max(48, 76 * scale))
        textView.textContainer?.containerSize = NSSize(
            width: max(240, visibleWidth - (sideInset * 2)),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.frame.size.width = visibleWidth
        updateDocumentHeight()
        annotationOverlay.frame = textView.bounds
        annotationOverlay.needsDisplay = true
        minimapView.needsDisplay = true
    }

    private func updateDocumentHeight() {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let laidOutHeight = ceil(textView.textContainerOrigin.y + usedRect.maxY + textView.textContainerInset.height)
        textView.frame.size.height = max(scrollView.contentSize.height, laidOutHeight)
    }

    private func updateScaledChrome() {
        let theme = currentTheme
        titleLabel.font = theme.smallFont
        statusLabel.font = theme.smallFont
        titleLabel.textColor = theme.secondaryTextColor
        statusLabel.textColor = theme.secondaryTextColor

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
        ruleTopConstraint?.constant = max(38, theme.scaledMetric(44))
    }

    private var currentTheme: MarkdownTheme {
        textView.styler.theme
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
