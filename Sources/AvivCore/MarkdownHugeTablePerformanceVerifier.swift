import AppKit
import Darwin
import Foundation

public struct MarkdownHugeTablePerformanceResult {
    public let passed: Bool
    public let failures: [String]
    public let rowCount: Int
    public let documentLength: Int
    public let loadLatency: TimeInterval
    public let initialRenderLatency: TimeInterval
    public let scrollLatencies: [TimeInterval]
    public let averageEditLatency: TimeInterval
    public let maximumEditLatency: TimeInterval
    public let residentMemoryBeforeLoad: UInt64
    public let residentMemoryAfterLoad: UInt64
    public let residentMemoryAfterInteractions: UInt64
    public let sourcePreserved: Bool
    public let searchPreserved: Bool
}

@MainActor
public enum MarkdownHugeTablePerformanceVerifier {
    private static let scrollFrameBudget: TimeInterval = 1.0 / 30.0

    public static func verify(
        rowCount: Int = 4_000,
        evidenceDirectory: URL? = nil
    ) -> MarkdownHugeTablePerformanceResult {
        precondition(rowCount >= 1_000, "huge-table benchmark requires at least 1,000 rows")

        let markdown = fixture(rowCount: rowCount)
        let workspace = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 1_040, height: 740)
        )
        workspace.updateDocumentTitle(
            url: URL(fileURLWithPath: "Huge Table Performance.md"),
            isEdited: false
        )
        workspace.layoutSubtreeIfNeeded()
        let residentMemoryBeforeLoad = residentMemory()

        let loadStart = CFAbsoluteTimeGetCurrent()
        workspace.loadMarkdown(markdown)
        workspace.layoutSubtreeIfNeeded()
        let loadLatency = CFAbsoluteTimeGetCurrent() - loadStart
        let residentMemoryAfterLoad = residentMemory()

        guard let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) else {
            preconditionFailure("could not allocate huge-table benchmark bitmap")
        }
        bitmap.size = workspace.bounds.size

        let initialRenderLatency = render(workspace, into: bitmap)
        let scrollLatencies = measureScrollFrames(workspace, bitmap: bitmap)
        centerOnEditTarget(workspace, rowCount: rowCount)
        _ = render(workspace, into: bitmap)

        let editResult = measureEdits(workspace, rowCount: rowCount)
        drainDeferredUpdates()
        _ = render(workspace, into: bitmap)
        let residentMemoryAfterInteractions = residentMemory()

        let sourcePreserved = workspace.textView.string == editResult.expectedSource
        let searchNeedle = "Search preservation sentinel row \(rowCount - 9)"
        let searchPreserved = (workspace.textView.string as NSString).range(of: searchNeedle)
            .location != NSNotFound

        centerOnEditTarget(workspace, rowCount: rowCount)
        _ = render(workspace, into: bitmap)
        writeScreenshot(bitmap, to: evidenceDirectory)

        let sortedScrollLatencies = scrollLatencies.sorted()
        let p95ScrollLatency = percentile(sortedScrollLatencies, percentile: 0.95)
        let maximumScrollLatency = sortedScrollLatencies.last ?? 0
        let jankyFrameCount = scrollLatencies.filter { $0 > scrollFrameBudget }.count
        let memoryGrowth = residentMemoryAfterInteractions > residentMemoryBeforeLoad
            ? residentMemoryAfterInteractions - residentMemoryBeforeLoad
            : 0

        var failures: [String] = []
        if loadLatency > 2.0 {
            failures.append(
                String(format: "load latency %.1f ms exceeded 2,000 ms", loadLatency * 1_000)
            )
        }
        if initialRenderLatency > 0.75 {
            failures.append(
                String(
                    format: "initial render latency %.1f ms exceeded 750 ms",
                    initialRenderLatency * 1_000
                )
            )
        }
        if p95ScrollLatency > scrollFrameBudget {
            failures.append(
                String(
                    format: "p95 scroll latency %.1f ms exceeded %.1f ms",
                    p95ScrollLatency * 1_000,
                    scrollFrameBudget * 1_000
                )
            )
        }
        if maximumScrollLatency > 0.100 {
            failures.append(
                String(
                    format: "maximum scroll latency %.1f ms exceeded 100 ms",
                    maximumScrollLatency * 1_000
                )
            )
        }
        if jankyFrameCount > 1 {
            failures.append(
                "\(jankyFrameCount) of \(scrollLatencies.count) measured scroll frames missed 30 fps"
            )
        }
        if editResult.averageLatency > 0.035 {
            failures.append(
                String(
                    format: "average edit latency %.1f ms exceeded 35 ms",
                    editResult.averageLatency * 1_000
                )
            )
        }
        if editResult.maximumLatency > 0.150 {
            failures.append(
                String(
                    format: "maximum edit latency %.1f ms exceeded 150 ms",
                    editResult.maximumLatency * 1_000
                )
            )
        }
        if memoryGrowth > 192 * 1_024 * 1_024 {
            failures.append(
                String(
                    format: "resident memory grew by %.1f MiB, exceeding 192 MiB",
                    mebibytes(memoryGrowth)
                )
            )
        }
        if !sourcePreserved {
            failures.append("huge-table interactions changed source outside the expected edits")
        }
        if !searchPreserved {
            failures.append("search could not find a sentinel near the end of the huge table")
        }

        let result = MarkdownHugeTablePerformanceResult(
            passed: failures.isEmpty,
            failures: failures,
            rowCount: rowCount,
            documentLength: (workspace.textView.string as NSString).length,
            loadLatency: loadLatency,
            initialRenderLatency: initialRenderLatency,
            scrollLatencies: scrollLatencies,
            averageEditLatency: editResult.averageLatency,
            maximumEditLatency: editResult.maximumLatency,
            residentMemoryBeforeLoad: residentMemoryBeforeLoad,
            residentMemoryAfterLoad: residentMemoryAfterLoad,
            residentMemoryAfterInteractions: residentMemoryAfterInteractions,
            sourcePreserved: sourcePreserved,
            searchPreserved: searchPreserved
        )
        writeSummary(result, to: evidenceDirectory)
        return result
    }

    public static func runCLI(evidenceDirectory: URL? = nil) -> Int32 {
        let result = verify(evidenceDirectory: evidenceDirectory)
        let sortedScrollLatencies = result.scrollLatencies.sorted()
        let p95 = percentile(sortedScrollLatencies, percentile: 0.95)
        let maximumScroll = sortedScrollLatencies.last ?? 0
        let memoryGrowth = result.residentMemoryAfterInteractions > result.residentMemoryBeforeLoad
            ? result.residentMemoryAfterInteractions - result.residentMemoryBeforeLoad
            : 0
        let summary = String(
            format:
                "%d rows/%d chars, load %.1f ms, first %.1f ms, scroll p95/max %.1f/%.1f ms, edit avg/max %.1f/%.1f ms, memory +%.1f MiB",
            result.rowCount,
            result.documentLength,
            result.loadLatency * 1_000,
            result.initialRenderLatency * 1_000,
            p95 * 1_000,
            maximumScroll * 1_000,
            result.averageEditLatency * 1_000,
            result.maximumEditLatency * 1_000,
            mebibytes(memoryGrowth)
        )

        if result.passed {
            print("huge-table-performance-verifier: PASS (\(summary))")
            return 0
        }

        print("huge-table-performance-verifier: FAIL (\(summary))")
        for failure in result.failures {
            print("- \(failure)")
        }
        return 1
    }

    private struct EditResult {
        let averageLatency: TimeInterval
        let maximumLatency: TimeInterval
        let expectedSource: String
    }

    private static func measureScrollFrames(
        _ workspace: EditorWorkspaceView,
        bitmap: NSBitmapImageRep
    ) -> [TimeInterval] {
        let ratios: [CGFloat] = [
            0.08, 0.24, 0.42, 0.61, 0.79, 0.96,
            0.82, 0.64, 0.45, 0.27, 0.10,
            0.35, 0.58, 0.88, 0.50,
        ]
        let clipView = workspace.scrollView.contentView
        let maximumY = max(0, workspace.textView.frame.height - clipView.bounds.height)

        return ratios.map { ratio in
            let start = CFAbsoluteTimeGetCurrent()
            clipView.scroll(to: NSPoint(x: 0, y: maximumY * ratio))
            workspace.scrollView.reflectScrolledClipView(clipView)
            workspace.layoutSubtreeIfNeeded()
            workspace.needsDisplay = true
            workspace.textView.needsDisplay = true
            workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
            return CFAbsoluteTimeGetCurrent() - start
        }
    }

    private static func measureEdits(
        _ workspace: EditorWorkspaceView,
        rowCount: Int
    ) -> EditResult {
        let editNeedle = "editable-value-\(rowCount / 2)-typing-marker-"
        var expectedSource = workspace.textView.string
        var measurements: [TimeInterval] = []

        for index in 0..<16 {
            let source = workspace.textView.string as NSString
            let targetRange = source.range(of: editNeedle)
            precondition(targetRange.location != NSNotFound, "missing huge-table edit target")
            let replacement = index.isMultiple(of: 2) ? "A" : "B"
            let editRange = NSRange(location: NSMaxRange(targetRange), length: 1)
            workspace.textView.setSelectedRange(editRange)

            let start = CFAbsoluteTimeGetCurrent()
            guard workspace.textView.shouldChangeText(
                in: editRange,
                replacementString: replacement
            ) else {
                preconditionFailure("huge-table benchmark edit was rejected")
            }
            workspace.textView.replaceCharacters(in: editRange, with: replacement)
            workspace.textView.didChangeText()
            workspace.textView.setSelectedRange(
                NSRange(location: editRange.location + 1, length: 0)
            )
            expectedSource = (expectedSource as NSString).replacingCharacters(
                in: editRange,
                with: replacement
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if index >= 3 {
                measurements.append(elapsed)
            }
        }

        let average = measurements.reduce(0, +) / Double(max(1, measurements.count))
        return EditResult(
            averageLatency: average,
            maximumLatency: measurements.max() ?? 0,
            expectedSource: expectedSource
        )
    }

    private static func centerOnEditTarget(_ workspace: EditorWorkspaceView, rowCount: Int) {
        let needle = "editable-value-\(rowCount / 2)-typing-marker-"
        let range = (workspace.textView.string as NSString).range(of: needle)
        precondition(range.location != NSNotFound, "missing huge-table center target")
        guard let layoutManager = workspace.textView.layoutManager,
            let textContainer = workspace.textView.textContainer
        else {
            preconditionFailure("missing huge-table text layout")
        }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.y += workspace.textView.textContainerOrigin.y
        let clipView = workspace.scrollView.contentView
        let maximumY = max(0, workspace.textView.frame.height - clipView.bounds.height)
        let targetY = min(max(0, rect.midY - clipView.bounds.height * 0.5), maximumY)
        clipView.scroll(to: NSPoint(x: 0, y: targetY))
        workspace.scrollView.reflectScrolledClipView(clipView)
    }

    private static func render(
        _ workspace: EditorWorkspaceView,
        into bitmap: NSBitmapImageRep
    ) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        workspace.layoutSubtreeIfNeeded()
        workspace.needsDisplay = true
        workspace.textView.needsDisplay = true
        workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
        return CFAbsoluteTimeGetCurrent() - start
    }

    private static func drainDeferredUpdates() {
        let deadline = Date(timeIntervalSinceNow: 0.25)
        while RunLoop.main.run(mode: .default, before: deadline), Date() < deadline {}
    }

    private static func residentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        precondition(result == KERN_SUCCESS, "could not read resident memory")
        return UInt64(info.resident_size)
    }

    private static func fixture(rowCount: Int) -> String {
        var lines: [String] = [
            "# Huge Table Performance Fixture",
            "",
            "| Index | Account | Region | Status | Updated | Detail | Search |",
            "| ---: | --- | --- | --- | --- | --- | --- |",
        ]
        lines.reserveCapacity(rowCount + 6)
        for row in 0..<rowCount {
            let editValue = row == rowCount / 2
                ? "editable-value-\(row)-typing-marker-X"
                : "stable-value-\(row)"
            let searchValue = row == rowCount - 9
                ? "Search preservation sentinel row \(row)"
                : "Indexed record \(row)"
            lines.append(
                "| \(row) | Account \(row) | Region \(row % 12) | Active | 2026-08-24 | \(editValue) | \(searchValue) |"
            )
        }
        lines.append("")
        lines.append("End-of-document integrity sentinel.")
        return lines.joined(separator: "\n")
    }

    private static func percentile(
        _ sortedValues: [TimeInterval],
        percentile: Double
    ) -> TimeInterval {
        guard !sortedValues.isEmpty else { return 0 }
        let index = min(
            sortedValues.count - 1,
            Int(ceil(Double(sortedValues.count) * percentile)) - 1
        )
        return sortedValues[max(0, index)]
    }

    private static func mebibytes(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_048_576
    }

    private static func writeScreenshot(
        _ bitmap: NSBitmapImageRep,
        to directory: URL?
    ) {
        guard let directory else { return }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("could not encode huge-table benchmark screenshot")
        }
        write(png, named: "huge-table-mid-scroll.png", to: directory)
    }

    private static func writeSummary(
        _ result: MarkdownHugeTablePerformanceResult,
        to directory: URL?
    ) {
        guard let directory else { return }
        let sorted = result.scrollLatencies.sorted()
        let summary: [String: Any] = [
            "passed": result.passed,
            "failures": result.failures,
            "rowCount": result.rowCount,
            "documentLength": result.documentLength,
            "loadMilliseconds": result.loadLatency * 1_000,
            "initialRenderMilliseconds": result.initialRenderLatency * 1_000,
            "scrollMilliseconds": result.scrollLatencies.map { $0 * 1_000 },
            "scrollP95Milliseconds": percentile(sorted, percentile: 0.95) * 1_000,
            "scrollMaximumMilliseconds": (sorted.last ?? 0) * 1_000,
            "jankyScrollFrameCount": result.scrollLatencies.filter {
                $0 > scrollFrameBudget
            }.count,
            "averageEditMilliseconds": result.averageEditLatency * 1_000,
            "maximumEditMilliseconds": result.maximumEditLatency * 1_000,
            "residentMemoryBeforeLoadBytes": result.residentMemoryBeforeLoad,
            "residentMemoryAfterLoadBytes": result.residentMemoryAfterLoad,
            "residentMemoryAfterInteractionsBytes": result.residentMemoryAfterInteractions,
            "sourcePreserved": result.sourcePreserved,
            "searchPreserved": result.searchPreserved,
        ]
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: summary,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(
                to: directory.appendingPathComponent("huge-table-performance-result.json"),
                options: [.atomic]
            )
        } catch {
            preconditionFailure("could not write huge-table benchmark summary: \(error)")
        }
    }

    private static func write(_ data: Data, named name: String, to directory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic])
        } catch {
            preconditionFailure("could not write huge-table benchmark evidence: \(error)")
        }
    }
}
