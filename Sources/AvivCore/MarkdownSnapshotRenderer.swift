import AppKit
import Foundation

public enum MarkdownSnapshotRenderer {
    public static func renderSample(
        to url: URL,
        width: CGFloat = 1180,
        height: CGFloat = 1480,
        cursorNeedle: String? = nil,
        viewScale: CGFloat? = nil,
        markdown: String = MarkdownSamples.starter,
        baseURL: URL? = nil,
        scrollRatio: CGFloat? = nil,
        documentFormat: MarkdownDocumentFormat = .blog
    ) throws {
        let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        workspace.documentFormat = documentFormat
        workspace.setDocumentURL(baseURL?.appendingPathComponent("Snapshot.md"))
        if let viewScale {
            workspace.textView.setViewScale(viewScale)
        }
        workspace.loadMarkdown(markdown)
        workspace.updateDocumentTitle(url: URL(fileURLWithPath: "Aviv Markdown.md"), isEdited: false)
        workspace.layoutSubtreeIfNeeded()

        if let cursorNeedle {
            let ns = workspace.textView.string as NSString
            let range = ns.range(of: cursorNeedle)
            if range.location != NSNotFound {
                workspace.textView.setSelectedRange(NSRange(location: range.location, length: 0))
            }
        } else {
            workspace.textView.setSelectedRange(NSRange(location: (workspace.textView.string as NSString).length, length: 0))
        }

        if let scrollRatio {
            scroll(workspace, to: scrollRatio)
        }

        if ProcessInfo.processInfo.environment["AVIV_DEBUG_SNAPSHOT"] == "1" {
            let ranges = workspace.textView.selectedRanges.compactMap { $0.rangeValue }
            let tokens = MarkdownAnnotationParser.tokens(in: workspace.textView.string, selectedRanges: ranges)
            print("snapshot debug: cursor=\(cursorNeedle ?? "nil") contains=\(workspace.textView.string.contains(cursorNeedle ?? "")) ranges=\(ranges) tokens=\(tokens.map { $0.label })")
        }

        workspace.layoutSubtreeIfNeeded()
        workspace.displayIfNeeded()

        guard let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = workspace.bounds.size
        workspace.cacheDisplay(in: workspace.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: [.atomic])
    }

    public static func renderMinimapFixture(
        to url: URL,
        width: CGFloat = 1180,
        height: CGFloat = 920,
        scrollRatio: CGFloat,
        viewScale: CGFloat? = nil
    ) throws {
        try renderSample(
            to: url,
            width: width,
            height: height,
            cursorNeedle: nil,
            viewScale: viewScale,
            markdown: MarkdownSamples.minimapFixture,
            baseURL: nil,
            scrollRatio: scrollRatio,
            documentFormat: .blog
        )
    }

    public static func renderPrintSample(
        to url: URL,
        format: MarkdownDocumentFormat = .a4,
        markdown: String = MarkdownSamples.starter,
        baseURL: URL? = nil
    ) throws {
        let paperSize = format.paperSize
        let margins = format.printMargins
        let printableWidth = paperSize.width - margins.left - margins.right
        let printView = MarkdownPrintView(
            markdown: markdown,
            printableWidth: printableWidth,
            format: format,
            baseURL: baseURL
        )
        printView.layoutSubtreeIfNeeded()

        let canvas = PrintPreviewCanvas(
            printView: printView,
            paperSize: paperSize,
            margins: margins
        )
        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()

        guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: [.atomic])
    }

    private static func scroll(_ workspace: EditorWorkspaceView, to ratio: CGFloat) {
        workspace.layoutSubtreeIfNeeded()
        guard let metrics = workspace.minimapForTesting.viewportMetrics() else { return }
        let clampedRatio = min(max(0, ratio), 1)
        let targetY = metrics.scrollableDocumentHeight * clampedRatio
        workspace.scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        workspace.scrollView.reflectScrolledClipView(workspace.scrollView.contentView)
        workspace.layoutSubtreeIfNeeded()
    }
}

private final class PrintPreviewCanvas: NSView {
    private let printView: MarkdownPrintView
    private let paperRect: NSRect
    private let margins: NSEdgeInsets

    init(printView: MarkdownPrintView, paperSize: NSSize, margins: NSEdgeInsets) {
        self.printView = printView
        self.paperRect = NSRect(x: 28, y: 28, width: paperSize.width, height: paperSize.height)
        self.margins = margins
        super.init(frame: NSRect(x: 0, y: 0, width: paperSize.width + 56, height: paperSize.height + 56))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.96, alpha: 1).cgColor
        addSubview(printView)
        positionPrintView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        positionPrintView()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.96, alpha: 1).setFill()
        dirtyRect.fill()
        NSColor.white.setFill()
        NSBezierPath(rect: paperRect).fill()
        NSColor(calibratedWhite: 0, alpha: 0.10).setStroke()
        NSBezierPath(rect: paperRect).stroke()
    }

    private func positionPrintView() {
        printView.frame.origin = NSPoint(
            x: paperRect.minX + margins.left,
            y: paperRect.minY + margins.top
        )
    }
}
