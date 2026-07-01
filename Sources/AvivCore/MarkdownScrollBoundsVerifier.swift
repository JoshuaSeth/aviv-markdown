import AppKit
import Foundation

public struct MarkdownScrollBoundsVerificationResult {
    public let passed: Bool
    public let failures: [String]
    public let measuredFixtures: Int
}

public enum MarkdownScrollBoundsVerifier {
    public static func verify() -> MarkdownScrollBoundsVerificationResult {
        var failures: [String] = []
        var measuredFixtures = 0

        for fixture in fixtures {
            let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: fixture.width, height: fixture.height))
            workspace.documentFormat = fixture.format
            if let viewScale = fixture.viewScale {
                workspace.textView.setTextScale(viewScale)
            }
            workspace.loadMarkdown(fixture.markdown)
            settle(workspace)

            measuredFixtures += 1
            failures.append(contentsOf: verifyScrollInsets(workspace, fixtureName: fixture.name))
            failures.append(contentsOf: verifyTopReachability(workspace, fixtureName: fixture.name))
        }

        return MarkdownScrollBoundsVerificationResult(
            passed: failures.isEmpty,
            failures: failures,
            measuredFixtures: measuredFixtures
        )
    }

    public static func runCLI() -> Int32 {
        let result = verify()
        if result.passed {
            print("scroll-bounds-verifier: PASS (\(result.measuredFixtures) fixtures)")
            return 0
        }

        print("scroll-bounds-verifier: FAIL")
        for failure in result.failures {
            print("- \(failure)")
        }
        return 1
    }

    private struct Fixture {
        let name: String
        let markdown: String
        let width: CGFloat
        let height: CGFloat
        let format: MarkdownDocumentFormat
        let viewScale: CGFloat?
    }

    private static let fixtures: [Fixture] = [
        Fixture(
            name: "blog-long",
            markdown: topScrollFixture,
            width: 1040,
            height: 740,
            format: .blog,
            viewScale: nil
        ),
        Fixture(
            name: "a4-long",
            markdown: topScrollFixture,
            width: 1040,
            height: 740,
            format: .a4,
            viewScale: nil
        ),
        Fixture(
            name: "zoomed-narrow",
            markdown: topScrollFixture,
            width: 680,
            height: 540,
            format: .blog,
            viewScale: 1.18
        )
    ]

    private static func verifyScrollInsets(_ workspace: EditorWorkspaceView, fixtureName: String) -> [String] {
        var failures: [String] = []

        if workspace.scrollView.automaticallyAdjustsContentInsets {
            failures.append("\(fixtureName): scroll view automatically adjusts content insets")
        }
        if !isZero(workspace.scrollView.contentInsets) {
            failures.append("\(fixtureName): scroll view has nonzero contentInsets \(workspace.scrollView.contentInsets)")
        }
        if !isZero(workspace.scrollView.scrollerInsets) {
            failures.append("\(fixtureName): scroll view has nonzero scrollerInsets \(workspace.scrollView.scrollerInsets)")
        }

        return failures
    }

    private static func verifyTopReachability(_ workspace: EditorWorkspaceView, fixtureName: String) -> [String] {
        var failures: [String] = []

        scroll(workspace, toY: bottomY(in: workspace))
        settle(workspace)
        scroll(workspace, toY: 0)
        settle(workspace)
        failures.append(contentsOf: verifyCurrentTop(workspace, fixtureName: fixtureName, mode: "bottom-to-top"))

        scroll(workspace, toY: bottomY(in: workspace))
        settle(workspace)
        scroll(workspace, toY: -500)
        settle(workspace)
        failures.append(contentsOf: verifyCurrentTop(workspace, fixtureName: fixtureName, mode: "negative-overscroll"))

        scroll(workspace, toY: bottomY(in: workspace))
        settle(workspace)
        if let metrics = workspace.minimapForTesting.viewportMetrics() {
            workspace.minimapForTesting.scrollForTesting(thumbMinY: metrics.trackRect.minY)
            settle(workspace)
            failures.append(contentsOf: verifyCurrentTop(workspace, fixtureName: fixtureName, mode: "minimap-thumb-top"))
        } else {
            failures.append("\(fixtureName): missing minimap metrics for top-scroll verification")
        }

        return failures
    }

    private static func verifyCurrentTop(
        _ workspace: EditorWorkspaceView,
        fixtureName: String,
        mode: String
    ) -> [String] {
        let visibleRect = workspace.scrollView.contentView.documentVisibleRect
        var failures: [String] = []

        if abs(visibleRect.minY) > 0.5 {
            failures.append("\(fixtureName)@\(mode): visible top is \(visibleRect.minY), expected 0")
        }

        guard let firstRect = rect(forNeedle: "Top Scroll Fixture", in: workspace.textView) else {
            failures.append("\(fixtureName)@\(mode): could not locate first rendered heading")
            return failures
        }

        let topGap = firstRect.minY - visibleRect.minY
        let expectedTopInset = workspace.textView.textContainerInset.height
        if topGap < -0.5 {
            failures.append("\(fixtureName)@\(mode): first heading is clipped above the visible top by \(abs(topGap)) pt")
        }
        if topGap > expectedTopInset + 24 {
            failures.append("\(fixtureName)@\(mode): first heading has extra top gap \(topGap) pt; expected near inset \(expectedTopInset) pt")
        }

        if let metrics = workspace.minimapForTesting.viewportMetrics(),
           abs(metrics.visibleMinY) > 0.5 {
            failures.append("\(fixtureName)@\(mode): minimap visibleMinY is \(metrics.visibleMinY), expected 0")
        }

        return failures
    }

    private static func rect(forNeedle needle: String, in textView: NSTextView) -> NSRect? {
        let nsString = textView.string as NSString
        let range = nsString.range(of: needle)
        guard range.location != NSNotFound,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }

        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    private static func scroll(_ workspace: EditorWorkspaceView, toY y: CGFloat) {
        workspace.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        workspace.scrollView.reflectScrolledClipView(workspace.scrollView.contentView)
    }

    private static func bottomY(in workspace: EditorWorkspaceView) -> CGFloat {
        max(0, workspace.textView.frame.height - workspace.scrollView.contentView.bounds.height)
    }

    private static func settle(_ workspace: EditorWorkspaceView) {
        workspace.layoutSubtreeIfNeeded()
        if let textContainer = workspace.textView.textContainer {
            workspace.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        workspace.layoutSubtreeIfNeeded()
        workspace.displayIfNeeded()
    }

    private static func isZero(_ insets: NSEdgeInsets) -> Bool {
        abs(insets.top) <= 0.01 &&
            abs(insets.left) <= 0.01 &&
            abs(insets.bottom) <= 0.01 &&
            abs(insets.right) <= 0.01
    }

    private static var topScrollFixture: String {
        (0..<48).map { index in
            """
            ## \(index == 0 ? "Top Scroll Fixture" : "Top Scroll Section \(index + 1)")

            This document verifies that the editor can always return completely to the top after bottom scrolling, minimap dragging, overscroll attempts, layout updates, and zoom changes. The first heading should remain reachable and visible below the chrome without hidden automatic scroll insets.

            - Top reachability sample \(index + 1).1
            - Top reachability sample \(index + 1).2 with `inline code` and [a reference](https://example.com/top/\(index)).

            """
        }.joined(separator: "\n")
    }
}
