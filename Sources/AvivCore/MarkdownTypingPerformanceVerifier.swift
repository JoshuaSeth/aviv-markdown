import AppKit
import Foundation

public struct MarkdownTypingPerformanceResult {
    public let passed: Bool
    public let failures: [String]
    public let editCount: Int
    public let documentLength: Int
    public let averageEditLatency: TimeInterval
    public let maxEditLatency: TimeInterval
}

@MainActor
public enum MarkdownTypingPerformanceVerifier {
    public static func verify(editCount: Int = 72) -> MarkdownTypingPerformanceResult {
        let workspace = EditorWorkspaceView(frame: NSRect(x: 0, y: 0, width: 1040, height: 740))
        let fixture = largeTypingFixture
        workspace.loadMarkdown(fixture)
        settle(workspace)

        let nsString = workspace.textView.string as NSString
        let needle = "Typing performance target 120: "
        let targetRange = nsString.range(of: needle)
        precondition(targetRange.location != NSNotFound, "missing typing performance target")

        var insertionLocation = targetRange.location + targetRange.length
        workspace.textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
        center(
            workspace,
            around: NSRange(location: insertionLocation, length: 1),
            visibleFraction: 0.55
        )
        settle(workspace)

        var measurements: [TimeInterval] = []
        for index in 0..<editCount {
            let range = NSRange(location: insertionLocation, length: 0)
            workspace.textView.setSelectedRange(range)

            let start = CFAbsoluteTimeGetCurrent()
            if workspace.textView.shouldChangeText(in: range, replacementString: "x") {
                workspace.textView.replaceCharacters(in: range, with: "x")
                workspace.textView.didChangeText()
                insertionLocation += 1
                workspace.textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            if index >= 4 {
                measurements.append(elapsed)
            }
        }

        let average = measurements.reduce(0, +) / Double(max(1, measurements.count))
        let maximum = measurements.max() ?? 0
        var failures: [String] = []

        if average > 0.035 {
            failures.append(
                String(format: "average edit latency %.3f ms exceeded 35 ms", average * 1000)
            )
        }
        if maximum > 0.150 {
            failures.append(
                String(format: "max edit latency %.3f ms exceeded 150 ms", maximum * 1000)
            )
        }

        return MarkdownTypingPerformanceResult(
            passed: failures.isEmpty,
            failures: failures,
            editCount: measurements.count,
            documentLength: (workspace.textView.string as NSString).length,
            averageEditLatency: average,
            maxEditLatency: maximum
        )
    }

    public static func runCLI() -> Int32 {
        let result = verify()
        let summary = String(
            format: "%d edits in %d chars, avg %.3f ms, max %.3f ms",
            result.editCount,
            result.documentLength,
            result.averageEditLatency * 1000,
            result.maxEditLatency * 1000
        )

        if result.passed {
            print("typing-performance-verifier: PASS (\(summary))")
            return 0
        }

        print("typing-performance-verifier: FAIL (\(summary))")
        for failure in result.failures {
            print("- \(failure)")
        }
        return 1
    }

    private static func center(
        _ workspace: EditorWorkspaceView,
        around range: NSRange,
        visibleFraction: CGFloat
    ) {
        guard
            let layoutManager = workspace.textView.layoutManager,
            let textContainer = workspace.textView.textContainer
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += workspace.textView.textContainerOrigin.x
        rect.origin.y += workspace.textView.textContainerOrigin.y

        let clipView = workspace.scrollView.contentView
        let maxY = max(0, workspace.textView.frame.height - clipView.bounds.height)
        let targetY = min(max(0, rect.midY - clipView.bounds.height * visibleFraction), maxY)
        clipView.scroll(to: NSPoint(x: 0, y: targetY))
        workspace.scrollView.reflectScrolledClipView(clipView)
    }

    private static func settle(_ workspace: EditorWorkspaceView) {
        workspace.layoutSubtreeIfNeeded()
        if let textContainer = workspace.textView.textContainer {
            workspace.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        workspace.layoutSubtreeIfNeeded()
    }

    private static var largeTypingFixture: String {
        (0..<180).map { index in
            """
            ## Performance Section \(index + 1)

            Typing performance target \(index + 1): aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

            This paragraph intentionally looks like a real working document. It includes **bold spans**, _emphasis_, `inline code`, [reference links](https://example.com/perf/\(index)), and enough prose to make line wrapping and live markdown styling do meaningful work while typing remains interactive.

            - Operational note \(index + 1).1 keeps list styling active.
            - Operational note \(index + 1).2 keeps selection changes realistic.

            | Signal | Status | Owner |
            | --- | --- | --- |
            | Typing | Stable | Aviv |

            """
        }.joined(separator: "\n")
    }
}
