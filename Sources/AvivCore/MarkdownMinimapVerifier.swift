import AppKit
import Foundation

public struct MarkdownMinimapVerificationResult {
    public let passed: Bool
    public let failures: [String]
    public let measuredPositions: Int
}

public enum MarkdownMinimapVerifier {
    public static func verify() -> MarkdownMinimapVerificationResult {
        var failures: [String] = []
        var measuredPositions = 0

        for fixture in fixtures {
            let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: fixture.width, height: fixture.height))
            if let viewScale = fixture.viewScale {
                workspace.textView.setTextScale(viewScale)
            }
            workspace.loadMarkdown(fixture.markdown)
            settle(workspace)

            guard let initialMetrics = workspace.minimapForTesting.viewportMetrics() else {
                failures.append("\(fixture.name): missing initial minimap metrics")
                continue
            }

            if fixture.expectNoScroll, initialMetrics.scrollableDocumentHeight > 1 {
                failures.append("\(fixture.name): short document has phantom scroll height \(initialMetrics.scrollableDocumentHeight)")
            }

            for ratio in fixture.scrollRatios {
                scroll(workspace, toRatio: ratio)
                settle(workspace)
                measuredPositions += 1
                failures.append(contentsOf: verifyCurrentPosition(workspace, fixtureName: fixture.name, ratio: ratio))
            }

            workspace.minimapForTesting.scrollForTesting(centeredAtMinimapY: workspace.minimapForTesting.bounds.midY)
            settle(workspace)
            measuredPositions += 1
            failures.append(contentsOf: verifyCenteredScroll(workspace, fixtureName: fixture.name))

            if let metrics = workspace.minimapForTesting.viewportMetrics(), metrics.scrollableDocumentHeight > 1 {
                workspace.minimapForTesting.scrollForTesting(thumbMinY: metrics.trackRect.maxY - metrics.thumbRect.height)
                settle(workspace)
                measuredPositions += 1
                failures.append(contentsOf: verifyBottomScroll(workspace, fixtureName: fixture.name))
            }
        }

        return MarkdownMinimapVerificationResult(
            passed: failures.isEmpty,
            failures: failures,
            measuredPositions: measuredPositions
        )
    }

    public static func runCLI() -> Int32 {
        let result = verify()
        if result.passed {
            print("minimap-verifier: PASS (\(result.measuredPositions) positions)")
            return 0
        }

        print("minimap-verifier: FAIL")
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
        let viewScale: CGFloat?
        let scrollRatios: [CGFloat]
        let expectNoScroll: Bool
    }

    private static let fixtures: [Fixture] = [
        Fixture(
            name: "short",
            markdown: "# Short\n\nThis should fit without phantom blank scrolling.",
            width: 880,
            height: 620,
            viewScale: nil,
            scrollRatios: [0],
            expectNoScroll: true
        ),
        Fixture(
            name: "structured-long",
            markdown: MarkdownSamples.minimapFixture,
            width: 1040,
            height: 740,
            viewScale: nil,
            scrollRatios: [0, 0.15, 0.5, 0.85, 1],
            expectNoScroll: false
        ),
        Fixture(
            name: "narrow-wrapped-zoomed",
            markdown: wrappedLongFixture,
            width: 640,
            height: 560,
            viewScale: 1.18,
            scrollRatios: [0, 0.25, 0.5, 0.75, 1],
            expectNoScroll: false
        )
    ]

    private static func verifyCurrentPosition(
        _ workspace: EditorWorkspaceView,
        fixtureName: String,
        ratio: CGFloat
    ) -> [String] {
        guard let metrics = workspace.minimapForTesting.viewportMetrics() else {
            return ["\(fixtureName)@\(ratio): missing minimap metrics"]
        }

        var failures: [String] = []
        let visibleRect = workspace.scrollView.contentView.documentVisibleRect
        let expectedVisibleMinY = min(max(0, visibleRect.minY), max(0, metrics.documentHeight - metrics.visibleHeight))
        if abs(metrics.visibleMinY - expectedVisibleMinY) > 1 {
            failures.append("\(fixtureName)@\(ratio): metrics visibleMinY \(metrics.visibleMinY) != clip visibleMinY \(expectedVisibleMinY)")
        }

        let projectedTop = metrics.projectedY(forDocumentY: metrics.visibleMinY)
        let projectedBottom = metrics.projectedY(forDocumentY: metrics.visibleMaxY)
        let exactProjectedHeight = projectedBottom - projectedTop
        if abs(metrics.thumbRect.height - exactProjectedHeight) <= 0.75 {
            if abs(metrics.thumbRect.minY - projectedTop) > 0.75 {
                failures.append("\(fixtureName)@\(ratio): thumb top \(metrics.thumbRect.minY) != projected visible top \(projectedTop)")
            }
            if abs(metrics.thumbRect.maxY - projectedBottom) > 0.75 {
                failures.append("\(fixtureName)@\(ratio): thumb bottom \(metrics.thumbRect.maxY) != projected visible bottom \(projectedBottom)")
            }
        } else {
            let projectedCenter = metrics.projectedY(forDocumentY: metrics.visibleMinY + metrics.visibleHeight / 2)
            let clampedCenter = min(
                max(metrics.trackRect.minY + metrics.thumbRect.height / 2, projectedCenter),
                metrics.trackRect.maxY - metrics.thumbRect.height / 2
            )
            if abs(metrics.thumbRect.midY - clampedCenter) > 0.75 {
                failures.append("\(fixtureName)@\(ratio): minimum thumb center \(metrics.thumbRect.midY) != projected center \(clampedCenter)")
            }
        }

        if ratio == 0, abs(metrics.thumbRect.minY - metrics.trackRect.minY) > 0.75 {
            failures.append("\(fixtureName)@top: thumb does not start at track top")
        }
        if ratio == 1, metrics.scrollableDocumentHeight > 1, abs(metrics.thumbRect.maxY - metrics.trackRect.maxY) > 0.75 {
            failures.append("\(fixtureName)@bottom: thumb does not end at track bottom")
        }

        return failures
    }

    private static func verifyCenteredScroll(_ workspace: EditorWorkspaceView, fixtureName: String) -> [String] {
        guard let metrics = workspace.minimapForTesting.viewportMetrics(), metrics.scrollableDocumentHeight > 1 else {
            return []
        }

        let visibleCenterRatio = (metrics.visibleMinY + metrics.visibleHeight / 2) / metrics.documentHeight
        if abs(visibleCenterRatio - 0.5) > 0.015 {
            return ["\(fixtureName): minimap center click scrolled to center ratio \(visibleCenterRatio), expected 0.5"]
        }
        return []
    }

    private static func verifyBottomScroll(_ workspace: EditorWorkspaceView, fixtureName: String) -> [String] {
        guard let metrics = workspace.minimapForTesting.viewportMetrics() else {
            return ["\(fixtureName): missing bottom metrics"]
        }

        if abs(metrics.visibleMaxY - metrics.documentHeight) > 1.5 {
            return ["\(fixtureName): thumb drag to bottom ended at visibleMaxY \(metrics.visibleMaxY), documentHeight \(metrics.documentHeight)"]
        }
        return []
    }

    private static func scroll(_ workspace: EditorWorkspaceView, toRatio ratio: CGFloat) {
        guard let metrics = workspace.minimapForTesting.viewportMetrics() else { return }
        let targetY = min(max(0, ratio), 1) * metrics.scrollableDocumentHeight
        workspace.scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        workspace.scrollView.reflectScrolledClipView(workspace.scrollView.contentView)
    }

    private static func settle(_ workspace: EditorWorkspaceView) {
        workspace.layoutSubtreeIfNeeded()
        workspace.textView.layoutManager?.ensureLayout(for: workspace.textView.textContainer!)
        workspace.layoutSubtreeIfNeeded()
        workspace.displayIfNeeded()
    }

    private static var wrappedLongFixture: String {
        let sentence = "A deliberately long visual line keeps wrapping through the text container so the minimap has to follow rendered glyph fragments, not just source newline counts."
        return (0..<34).map { index in
            """
            ### Wrapped paragraph \(index + 1)

            \(Array(repeating: sentence, count: 6).joined(separator: " "))

            > Quoted wrap \(index + 1): \(Array(repeating: sentence, count: 2).joined(separator: " "))

            """
        }.joined(separator: "\n")
    }
}
