import AppKit
import Foundation

public struct MarkdownScrollJitterVerificationResult {
    public let passed: Bool
    public let failures: [String]
    public let measuredEdits: Int
    public let maxVisibleOriginDelta: CGFloat
    public let maxDocumentHeightDelta: CGFloat
    public let maxMinimapThumbDelta: CGFloat
}

public enum MarkdownScrollJitterVerifier {
    public static func verify() -> MarkdownScrollJitterVerificationResult {
        let fixtures = [
            Fixture(name: "same-length-overwrite", mode: .sameLengthOverwrite, editCount: 16, visibleFraction: 0.45),
            Fixture(name: "same-length-overwrite-lower-viewport", mode: .sameLengthOverwrite, editCount: 16, visibleFraction: 0.86),
            Fixture(name: "short-insertions-lower-viewport", mode: .shortInsertions, editCount: 12, visibleFraction: 0.86)
        ]

        var failures: [String] = []
        var measuredEdits = 0
        var maxVisibleOriginDelta: CGFloat = 0
        var maxDocumentHeightDelta: CGFloat = 0
        var maxMinimapThumbDelta: CGFloat = 0

        for fixture in fixtures {
            let result = run(fixture: fixture)
            measuredEdits += result.measuredEdits
            failures.append(contentsOf: result.failures)
            maxVisibleOriginDelta = max(maxVisibleOriginDelta, result.maxVisibleOriginDelta)
            maxDocumentHeightDelta = max(maxDocumentHeightDelta, result.maxDocumentHeightDelta)
            maxMinimapThumbDelta = max(maxMinimapThumbDelta, result.maxMinimapThumbDelta)
        }

        let transientResult = runStyleTransitionFixture()
        measuredEdits += transientResult.measuredEdits
        failures.append(contentsOf: transientResult.failures)
        maxVisibleOriginDelta = max(maxVisibleOriginDelta, transientResult.maxVisibleOriginDelta)
        maxDocumentHeightDelta = max(maxDocumentHeightDelta, transientResult.maxDocumentHeightDelta)
        maxMinimapThumbDelta = max(maxMinimapThumbDelta, transientResult.maxMinimapThumbDelta)

        return MarkdownScrollJitterVerificationResult(
            passed: failures.isEmpty,
            failures: failures,
            measuredEdits: measuredEdits,
            maxVisibleOriginDelta: maxVisibleOriginDelta,
            maxDocumentHeightDelta: maxDocumentHeightDelta,
            maxMinimapThumbDelta: maxMinimapThumbDelta
        )
    }

    public static func runCLI() -> Int32 {
        let result = verify()
        let summary = String(
            format: "origin %.3f pt, height %.3f pt, minimap %.3f pt",
            result.maxVisibleOriginDelta,
            result.maxDocumentHeightDelta,
            result.maxMinimapThumbDelta
        )

        if result.passed {
            print("scroll-jitter-verifier: PASS (\(result.measuredEdits) edits, \(summary))")
            return 0
        }

        print("scroll-jitter-verifier: FAIL (\(summary))")
        for failure in result.failures {
            print("- \(failure)")
        }
        return 1
    }

    public static func renderSnapshot(to url: URL) throws {
        let fixture = Fixture(name: "snapshot", mode: .shortInsertions, editCount: 12, visibleFraction: 0.86)
        let workspace = makeWorkspace()
        let anchor = prepare(workspace: workspace, for: fixture)
        performEdits(in: workspace, fixture: fixture, anchorLocation: anchor)
        settle(workspace)

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

    private enum EditMode {
        case sameLengthOverwrite
        case shortInsertions
    }

    private struct Fixture {
        let name: String
        let mode: EditMode
        let editCount: Int
        let visibleFraction: CGFloat
    }

    private struct Measurement {
        let visibleMinY: CGFloat
        let documentHeight: CGFloat
        let minimapThumbMinY: CGFloat
    }

    private static func run(fixture: Fixture) -> MarkdownScrollJitterVerificationResult {
        let workspace = makeWorkspace()
        let anchor = prepare(workspace: workspace, for: fixture)
        let baseline = measure(workspace)
        var measurements: [Measurement] = []

        performEdits(in: workspace, fixture: fixture, anchorLocation: anchor) {
            measurements.append(measure(workspace))
        }

        let visibleOriginValues = measurements.map(\.visibleMinY) + [baseline.visibleMinY]
        let documentHeightValues = measurements.map(\.documentHeight) + [baseline.documentHeight]
        let minimapThumbValues = measurements.map(\.minimapThumbMinY) + [baseline.minimapThumbMinY]

        let maxVisibleOriginDelta = spread(visibleOriginValues)
        let maxDocumentHeightDelta = spread(documentHeightValues)
        let maxMinimapThumbDelta = spread(minimapThumbValues)
        let maxOriginFromBaseline = maxDelta(from: baseline.visibleMinY, values: measurements.map(\.visibleMinY))
        let maxHeightFromBaseline = maxDelta(from: baseline.documentHeight, values: measurements.map(\.documentHeight))
        let maxThumbFromBaseline = maxDelta(from: baseline.minimapThumbMinY, values: measurements.map(\.minimapThumbMinY))

        var failures: [String] = []
        if maxVisibleOriginDelta > 0.75 || maxOriginFromBaseline > 0.75 {
            failures.append(
                String(
                    format: "%@: visible origin jittered by %.3f pt (baseline delta %.3f pt)",
                    fixture.name,
                    maxVisibleOriginDelta,
                    maxOriginFromBaseline
                )
            )
        }
        if maxDocumentHeightDelta > 1.0 || maxHeightFromBaseline > 1.0 {
            failures.append(
                String(
                    format: "%@: document height changed by %.3f pt (baseline delta %.3f pt)",
                    fixture.name,
                    maxDocumentHeightDelta,
                    maxHeightFromBaseline
                )
            )
        }
        if maxMinimapThumbDelta > 0.75 || maxThumbFromBaseline > 0.75 {
            failures.append(
                String(
                    format: "%@: minimap thumb jittered by %.3f pt (baseline delta %.3f pt)",
                    fixture.name,
                    maxMinimapThumbDelta,
                    maxThumbFromBaseline
                )
            )
        }

        return MarkdownScrollJitterVerificationResult(
            passed: failures.isEmpty,
            failures: failures,
            measuredEdits: measurements.count,
            maxVisibleOriginDelta: maxVisibleOriginDelta,
            maxDocumentHeightDelta: maxDocumentHeightDelta,
            maxMinimapThumbDelta: maxMinimapThumbDelta
        )
    }

    private static func runStyleTransitionFixture() -> MarkdownScrollJitterVerificationResult {
        let workspace = makeWorkspace()
        let nsString = workspace.textView.string as NSString
        let needle = "Style transition target 20: Heading candidate"
        let targetRange = nsString.range(of: needle)
        precondition(targetRange.location != NSNotFound, "missing style transition target")
        let lineRange = nsString.lineRange(for: targetRange)

        workspace.textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        center(workspace, around: NSRange(location: lineRange.location, length: 1), visibleFraction: 0.82)
        settle(workspace)

        var notificationMeasurement: Measurement?
        let observer = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: workspace.textView,
            queue: nil
        ) { _ in
            notificationMeasurement = measure(workspace)
        }

        workspace.textView.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "# ")
        workspace.textView.didChangeText()
        NotificationCenter.default.removeObserver(observer)
        settle(workspace)

        guard let notified = notificationMeasurement else {
            return MarkdownScrollJitterVerificationResult(
                passed: false,
                failures: ["style-transition-notification: missing text change notification measurement"],
                measuredEdits: 1,
                maxVisibleOriginDelta: 0,
                maxDocumentHeightDelta: 0,
                maxMinimapThumbDelta: 0
            )
        }

        let final = measure(workspace)
        let visibleOriginDelta = abs(final.visibleMinY - notified.visibleMinY)
        let documentHeightDelta = abs(final.documentHeight - notified.documentHeight)
        let minimapThumbDelta = abs(final.minimapThumbMinY - notified.minimapThumbMinY)
        var failures: [String] = []

        if documentHeightDelta > 1.0 || minimapThumbDelta > 0.75 {
            failures.append(
                String(
                    format: "style-transition-notification: text change notification used intermediate geometry (height %.3f pt, minimap %.3f pt)",
                    documentHeightDelta,
                    minimapThumbDelta
                )
            )
        }

        if visibleOriginDelta > 0.75 {
            failures.append(
                String(
                    format: "style-transition-notification: visible origin shifted between notification and final styled layout by %.3f pt",
                    visibleOriginDelta
                )
            )
        }

        return MarkdownScrollJitterVerificationResult(
            passed: failures.isEmpty,
            failures: failures,
            measuredEdits: 1,
            maxVisibleOriginDelta: visibleOriginDelta,
            maxDocumentHeightDelta: documentHeightDelta,
            maxMinimapThumbDelta: minimapThumbDelta
        )
    }

    private static func makeWorkspace() -> EditorWorkspaceView {
        let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: 1040, height: 740))
        workspace.loadMarkdown(scrollStabilityFixture)
        workspace.updateDocumentTitle(url: URL(fileURLWithPath: "Scroll Stability.md"), isEdited: false)
        settle(workspace)
        return workspace
    }

    private static func prepare(workspace: EditorWorkspaceView, for fixture: Fixture) -> Int {
        let nsString = workspace.textView.string as NSString
        let needle = "Stable typing target 20: "
        let targetRange = nsString.range(of: needle)
        precondition(targetRange.location != NSNotFound, "missing scroll stability target")
        let anchor = targetRange.location + targetRange.length

        workspace.textView.setSelectedRange(NSRange(location: anchor, length: 0))
        center(workspace, around: NSRange(location: anchor, length: 1), visibleFraction: fixture.visibleFraction)
        settle(workspace)
        workspace.textView.setSelectedRange(NSRange(location: anchor, length: fixture.mode == .sameLengthOverwrite ? 1 : 0))
        settle(workspace)
        return anchor
    }

    private static func performEdits(
        in workspace: EditorWorkspaceView,
        fixture: Fixture,
        anchorLocation: Int,
        afterEachEdit: (() -> Void)? = nil
    ) {
        switch fixture.mode {
        case .sameLengthOverwrite:
            for index in 0..<fixture.editCount {
                let location = anchorLocation + (index % 18)
                let range = NSRange(location: location, length: 1)
                workspace.textView.setSelectedRange(range)
                workspace.textView.replaceCharacters(in: range, with: "a")
                workspace.textView.didChangeText()
                workspace.textView.setSelectedRange(NSRange(location: location + 1, length: 0))
                settle(workspace)
                afterEachEdit?()
            }
        case .shortInsertions:
            for index in 0..<fixture.editCount {
                let location = anchorLocation + index
                let range = NSRange(location: location, length: 0)
                workspace.textView.setSelectedRange(range)
                workspace.textView.replaceCharacters(in: range, with: "x")
                workspace.textView.didChangeText()
                workspace.textView.setSelectedRange(NSRange(location: location + 1, length: 0))
                settle(workspace)
                afterEachEdit?()
            }
        }
    }

    private static func center(_ workspace: EditorWorkspaceView, around range: NSRange, visibleFraction: CGFloat) {
        guard
            let layoutManager = workspace.textView.layoutManager,
            let textContainer = workspace.textView.textContainer
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += workspace.textView.textContainerOrigin.x
        rect.origin.y += workspace.textView.textContainerOrigin.y

        let clipView = workspace.scrollView.contentView
        let maxY = max(0, workspace.textView.frame.height - clipView.bounds.height)
        let targetY = min(max(0, rect.midY - clipView.bounds.height * visibleFraction), maxY)
        clipView.scroll(to: NSPoint(x: 0, y: targetY))
        workspace.scrollView.reflectScrolledClipView(clipView)
    }

    private static func measure(_ workspace: EditorWorkspaceView) -> Measurement {
        let visibleRect = workspace.scrollView.contentView.documentVisibleRect
        let metrics = workspace.minimapForTesting.viewportMetrics()
        return Measurement(
            visibleMinY: rounded(visibleRect.minY),
            documentHeight: rounded(workspace.textView.frame.height),
            minimapThumbMinY: rounded(metrics?.thumbRect.minY ?? 0)
        )
    }

    private static func settle(_ workspace: EditorWorkspaceView) {
        workspace.layoutSubtreeIfNeeded()
        if let textContainer = workspace.textView.textContainer {
            workspace.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        workspace.layoutSubtreeIfNeeded()
    }

    private static func spread(_ values: [CGFloat]) -> CGFloat {
        guard let minimum = values.min(), let maximum = values.max() else { return 0 }
        return maximum - minimum
    }

    private static func maxDelta(from baseline: CGFloat, values: [CGFloat]) -> CGFloat {
        values.map { abs($0 - baseline) }.max() ?? 0
    }

    private static func rounded(_ value: CGFloat) -> CGFloat {
        (value * 1000).rounded() / 1000
    }

    private static var scrollStabilityFixture: String {
        (0..<32).map { index in
            """
            ## Scroll Stability Section \(index + 1)

            Stable typing target \(index + 1): aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

            Style transition target \(index + 1): Heading candidate

            This paragraph keeps the editor comfortably scrollable while staying far away from wrapping thresholds during the typing simulation. It includes **bold text**, _quiet emphasis_, `inline code`, [a reference link](https://example.com/scroll/\(index)), and ordinary prose so the normal live markdown styling path is exercised.

            - Item \(index + 1).1 keeps list layout in the document.
            - Item \(index + 1).2 keeps the minimap projection honest.

            """
        }.joined(separator: "\n")
    }
}
