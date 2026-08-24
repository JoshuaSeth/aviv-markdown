import AppKit
import Foundation

public struct MarkdownTableRestorationResult {
    public let passed: Bool
    public let failures: [String]
    public let documentLength: Int
    public let normalToEditingPixelDifference: Int
    public let normalToRestoredPixelDifference: Int
    public let maximumTableFrameDelta: CGFloat
    public let scrollOriginDelta: CGFloat
    public let sourcePreserved: Bool
    public let selectionPreserved: Bool
    public let attributesRestored: Bool
}

@MainActor
public enum MarkdownTableRestorationVerifier {
    public static func verify(evidenceDirectory: URL? = nil) -> MarkdownTableRestorationResult {
        let workspace = makeWorkspace()
        let markdown = workspace.textView.string
        let nsString = markdown as NSString
        let tableCellRange = nsString.range(of: "Visual restoration target")
        let outsideRange = nsString.range(of: "Focus destination outside the table")
        precondition(tableCellRange.location != NSNotFound, "missing table restoration target")
        precondition(outsideRange.location != NSNotFound, "missing outside focus target")

        workspace.textView.setSelectedRange(NSRange(location: outsideRange.location, length: 0))
        center(workspace, around: tableCellRange)
        settle(workspace)

        let baseline = snapshot(workspace, tableCellRange: tableCellRange)
        write(baseline.pngData, named: "table-normal.png", to: evidenceDirectory)

        workspace.textView.setSelectedRange(NSRange(location: tableCellRange.location, length: 0))
        settle(workspace)
        let editing = snapshot(workspace, tableCellRange: tableCellRange)
        write(editing.pngData, named: "table-editing.png", to: evidenceDirectory)

        workspace.textView.setSelectedRange(NSRange(location: outsideRange.location, length: 0))
        settle(workspace)
        let restored = snapshot(workspace, tableCellRange: tableCellRange)
        write(restored.pngData, named: "table-restored.png", to: evidenceDirectory)

        let normalToEditing = pixelDifference(baseline, editing)
        let normalToRestored = pixelDifference(baseline, restored)
        let maximumFrameDelta = rectDelta(baseline.tableFrame, restored.tableFrame)
        let scrollDelta = pointDelta(baseline.visibleOrigin, restored.visibleOrigin)
        let sourcePreserved = workspace.textView.string == markdown
        let selectionPreserved = workspace.textView.selectedRange()
            == NSRange(location: outsideRange.location, length: 0)
        let attributesRestored = baseline.tableAttributes.isEqual(to: restored.tableAttributes)

        var failures: [String] = []
        if normalToEditing == 0 {
            failures.append("Clicking a table row did not expose an editable visual state")
        }
        if normalToRestored != 0 {
            failures.append(
                "Post-edit table differs from the normal rendering by \(normalToRestored) pixel bytes"
            )
        }
        if !attributesRestored {
            failures.append("Post-edit table text attributes did not return to the normal attributes")
        }
        if maximumFrameDelta > 0.01 {
            failures.append(
                String(
                    format: "Post-edit table geometry drifted by %.3f pt",
                    maximumFrameDelta
                )
            )
        }
        if scrollDelta > 0.01 {
            failures.append(
                String(format: "Post-edit scroll origin drifted by %.3f pt", scrollDelta)
            )
        }
        if !selectionPreserved {
            failures.append("Click-away selection was not preserved")
        }
        if !sourcePreserved {
            failures.append("Table focus transition changed the Markdown source")
        }

        let result = MarkdownTableRestorationResult(
            passed: failures.isEmpty,
            failures: failures,
            documentLength: nsString.length,
            normalToEditingPixelDifference: normalToEditing,
            normalToRestoredPixelDifference: normalToRestored,
            maximumTableFrameDelta: maximumFrameDelta,
            scrollOriginDelta: scrollDelta,
            sourcePreserved: sourcePreserved,
            selectionPreserved: selectionPreserved,
            attributesRestored: attributesRestored
        )
        writeSummary(result, to: evidenceDirectory)
        return result
    }

    public static func runCLI(evidenceDirectory: URL? = nil) -> Int32 {
        let result = verify(evidenceDirectory: evidenceDirectory)
        let summary = String(
            format:
                "%d chars, editing delta %d, restored delta %d, frame %.3f pt, scroll %.3f pt",
            result.documentLength,
            result.normalToEditingPixelDifference,
            result.normalToRestoredPixelDifference,
            result.maximumTableFrameDelta,
            result.scrollOriginDelta
        )

        if result.passed {
            print("table-restoration-verifier: PASS (\(summary))")
            return 0
        }

        print("table-restoration-verifier: FAIL (\(summary))")
        for failure in result.failures {
            print("- \(failure)")
        }
        return 1
    }

    private struct Snapshot {
        let bitmapData: Data
        let pngData: Data
        let pixelsWide: Int
        let pixelsHigh: Int
        let bytesPerRow: Int
        let tableAttributes: NSAttributedString
        let tableFrame: NSRect
        let visibleOrigin: NSPoint
    }

    private static func makeWorkspace() -> EditorWorkspaceView {
        let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: 1040, height: 740))
        workspace.loadMarkdown(largeDocumentFixture)
        workspace.updateDocumentTitle(
            url: URL(fileURLWithPath: "Table Restoration.md"),
            isEdited: false
        )
        settle(workspace)
        return workspace
    }

    private static func snapshot(
        _ workspace: EditorWorkspaceView,
        tableCellRange: NSRange
    ) -> Snapshot {
        workspace.needsDisplay = true
        workspace.textView.needsDisplay = true
        workspace.displayIfNeeded()

        guard let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) else {
            preconditionFailure("could not allocate table restoration bitmap")
        }
        bitmap.size = workspace.bounds.size
        workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
        guard let bitmapPointer = bitmap.bitmapData,
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            preconditionFailure("could not encode table restoration bitmap")
        }

        let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
        let bitmapData = Data(bytes: bitmapPointer, count: byteCount)
        let tableBlock = MarkdownTableParser.block(
            containing: tableCellRange.location,
            in: workspace.textView.string
        )
        guard let tableBlock, let textStorage = workspace.textView.textStorage else {
            preconditionFailure("could not resolve table restoration block")
        }

        return Snapshot(
            bitmapData: bitmapData,
            pngData: pngData,
            pixelsWide: bitmap.pixelsWide,
            pixelsHigh: bitmap.pixelsHigh,
            bytesPerRow: bitmap.bytesPerRow,
            tableAttributes: textStorage.attributedSubstring(from: tableBlock.range),
            tableFrame: frame(for: tableBlock.range, in: workspace.textView),
            visibleOrigin: workspace.scrollView.contentView.bounds.origin
        )
    }

    private static func pixelDifference(_ lhs: Snapshot, _ rhs: Snapshot) -> Int {
        guard lhs.pixelsWide == rhs.pixelsWide,
            lhs.pixelsHigh == rhs.pixelsHigh,
            lhs.bytesPerRow == rhs.bytesPerRow,
            lhs.bitmapData.count == rhs.bitmapData.count
        else {
            return Int.max
        }

        return zip(lhs.bitmapData, rhs.bitmapData).reduce(into: 0) { difference, bytes in
            if bytes.0 != bytes.1 {
                difference += 1
            }
        }
    }

    private static func frame(for range: NSRange, in textView: NSTextView) -> NSRect {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer
        else {
            return .zero
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    private static func center(_ workspace: EditorWorkspaceView, around range: NSRange) {
        let rect = frame(for: range, in: workspace.textView)
        let clipView = workspace.scrollView.contentView
        let maximumY = max(0, workspace.textView.frame.height - clipView.bounds.height)
        let targetY = min(max(0, rect.midY - clipView.bounds.height * 0.48), maximumY)
        clipView.scroll(to: NSPoint(x: 0, y: targetY))
        workspace.scrollView.reflectScrolledClipView(clipView)
    }

    private static func settle(_ workspace: EditorWorkspaceView) {
        workspace.layoutSubtreeIfNeeded()
        if let textContainer = workspace.textView.textContainer {
            workspace.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        workspace.layoutSubtreeIfNeeded()
        workspace.displayIfNeeded()
    }

    private static func rectDelta(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        [
            abs(lhs.minX - rhs.minX),
            abs(lhs.minY - rhs.minY),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height),
        ].max() ?? 0
    }

    private static func pointDelta(_ lhs: NSPoint, _ rhs: NSPoint) -> CGFloat {
        max(abs(lhs.x - rhs.x), abs(lhs.y - rhs.y))
    }

    private static func write(_ data: Data, named name: String, to directory: URL?) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic])
        } catch {
            preconditionFailure("could not write table restoration evidence: \(error)")
        }
    }

    private static func writeSummary(
        _ result: MarkdownTableRestorationResult,
        to directory: URL?
    ) {
        guard let directory else { return }
        let summary: [String: Any] = [
            "passed": result.passed,
            "documentLength": result.documentLength,
            "normalToEditingPixelDifference": result.normalToEditingPixelDifference,
            "normalToRestoredPixelDifference": result.normalToRestoredPixelDifference,
            "maximumTableFrameDelta": result.maximumTableFrameDelta,
            "scrollOriginDelta": result.scrollOriginDelta,
            "sourcePreserved": result.sourcePreserved,
            "selectionPreserved": result.selectionPreserved,
            "attributesRestored": result.attributesRestored,
            "failures": result.failures,
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: summary,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(
                to: directory.appendingPathComponent("table-restoration-result.json"),
                options: [.atomic]
            )
        } catch {
            preconditionFailure("could not write table restoration summary: \(error)")
        }
    }

    private static var largeDocumentFixture: String {
        let prefix = (0..<54).map { index in
            "Baseline context \(index + 1): Aviv keeps this realistic report content stable."
        }.joined(separator: "\n")
        let suffix = (0..<120).map { index in
            "Trailing context \(index + 1): selection, scrolling, and rendering must remain exact."
        }.joined(separator: "\n")
        return """
            # Large Table Restoration Fixture

            \(prefix)

            | Signal | Status | Owner |
            | --- | --- | --- |
            | Visual restoration target | Exact normal rendering | Aviv |
            | Secondary row | Stable borders and spacing | Seth |

            Focus destination outside the table.

            \(suffix)
            """
    }
}
