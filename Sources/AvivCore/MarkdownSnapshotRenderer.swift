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
        scrollRatio: CGFloat? = nil
    ) throws {
        let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: width, height: height))
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
            scrollRatio: scrollRatio
        )
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
