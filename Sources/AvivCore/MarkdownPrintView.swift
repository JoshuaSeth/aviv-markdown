import AppKit

public final class MarkdownPrintView: NSView {
    public let textView: MarkdownTextView

    private let annotationOverlay: MarkdownAnnotationOverlayView
    private let printableWidth: CGFloat

    public init(
        markdown: String,
        printableWidth: CGFloat,
        format: MarkdownDocumentFormat = .a4,
        baseURL: URL? = nil,
        theme: MarkdownTheme = .clean
    ) {
        self.printableWidth = max(320, printableWidth)
        let printTheme = theme.withViewScale(format.printViewScale)
        self.textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: self.printableWidth, height: 1), styler: MarkdownStyler(theme: printTheme))
        self.annotationOverlay = MarkdownAnnotationOverlayView(textView: textView, theme: printTheme)
        super.init(frame: NSRect(x: 0, y: 0, width: self.printableWidth, height: 1))

        wantsLayer = false
        textView.frame = bounds
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: self.printableWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.markdownImageBaseURL = baseURL
        textView.loadMarkdownForPrint(markdown)

        annotationOverlay.frame = textView.bounds
        annotationOverlay.autoresizingMask = [.width, .height]
        textView.addSubview(annotationOverlay)
        addSubview(textView)
        updateDocumentHeight()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool {
        true
    }

    public override func layout() {
        super.layout()
        textView.frame.size.width = printableWidth
        textView.textContainer?.containerSize = NSSize(width: printableWidth, height: CGFloat.greatestFiniteMagnitude)
        updateDocumentHeight()
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
    }

    private func updateDocumentHeight() {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = max(1, ceil(usedRect.maxY + textView.textContainerInset.height * 2))
        frame = NSRect(x: 0, y: 0, width: printableWidth, height: height)
        textView.frame = bounds
        annotationOverlay.frame = textView.bounds
        annotationOverlay.needsDisplay = true
    }
}
