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
    public let scrollRenderLatencies: [TimeInterval]
    public let averageEditLatency: TimeInterval
    public let maximumEditLatency: TimeInterval
    public let residentMemoryBeforeLoad: UInt64
    public let residentMemoryAfterLoad: UInt64
    public let residentMemoryAfterInteractions: UInt64
    public let sourcePreserved: Bool
    public let searchPreserved: Bool
    public let copyPreserved: Bool
    public let pastePreserved: Bool
}

@MainActor
public enum MarkdownHugeTablePerformanceVerifier {
    private static let scrollUpdateBudget: TimeInterval = 1.0 / 60.0
    private static let scrollRenderBudget: TimeInterval = 0.100

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
        let scrollMeasurements = measureScrollFrames(workspace, bitmap: bitmap)
        centerOnEditTarget(workspace, rowCount: rowCount)
        _ = render(workspace, into: bitmap)

        let editResult = measureEdits(workspace, rowCount: rowCount)
        let copyPasteResult = verifyCopyPaste(
            workspace,
            rowCount: rowCount,
            expectedSource: editResult.expectedSource
        )
        drainDeferredUpdates()
        _ = render(workspace, into: bitmap)
        let residentMemoryAfterInteractions = residentMemory()

        let sourcePreserved = workspace.textView.string == copyPasteResult.expectedSource
        let searchNeedle = "Search preservation sentinel row \(rowCount - 9)"
        let searchPreserved =
            (workspace.textView.string as NSString).range(of: searchNeedle)
            .location != NSNotFound

        centerOnEditTarget(workspace, rowCount: rowCount)
        _ = render(workspace, into: bitmap)
        writeScreenshot(bitmap, to: evidenceDirectory)

        let scrollLatencies = scrollMeasurements.updateLatencies
        let scrollRenderLatencies = scrollMeasurements.renderLatencies
        let sortedScrollLatencies = scrollLatencies.sorted()
        let sortedScrollRenderLatencies = scrollRenderLatencies.sorted()
        let p95ScrollLatency = percentile(sortedScrollLatencies, percentile: 0.95)
        let maximumScrollLatency = sortedScrollLatencies.last ?? 0
        let p95ScrollRenderLatency = percentile(
            sortedScrollRenderLatencies,
            percentile: 0.95
        )
        let maximumScrollRenderLatency = sortedScrollRenderLatencies.last ?? 0
        let jankyFrameCount = scrollLatencies.filter { $0 > scrollUpdateBudget }.count
        let memoryGrowth =
            residentMemoryAfterInteractions > residentMemoryBeforeLoad
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
        if p95ScrollLatency > scrollUpdateBudget {
            failures.append(
                String(
                    format: "p95 scroll update latency %.1f ms exceeded %.1f ms",
                    p95ScrollLatency * 1_000,
                    scrollUpdateBudget * 1_000
                )
            )
        }
        if maximumScrollLatency > 0.050 {
            failures.append(
                String(
                    format: "maximum scroll update latency %.1f ms exceeded 50 ms",
                    maximumScrollLatency * 1_000
                )
            )
        }
        if jankyFrameCount > 1 {
            failures.append(
                "\(jankyFrameCount) of \(scrollLatencies.count) scroll updates missed 60 fps"
            )
        }
        if p95ScrollRenderLatency > scrollRenderBudget {
            failures.append(
                String(
                    format: "p95 scroll raster latency %.1f ms exceeded 100 ms",
                    p95ScrollRenderLatency * 1_000
                )
            )
        }
        if maximumScrollRenderLatency > 0.150 {
            failures.append(
                String(
                    format: "maximum scroll raster latency %.1f ms exceeded 150 ms",
                    maximumScrollRenderLatency * 1_000
                )
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
        if !copyPasteResult.copyPreserved {
            failures.append("copy did not preserve the selected source text in the huge table")
        }
        if !copyPasteResult.pastePreserved {
            failures.append("paste did not insert exact source text into the huge table")
        }

        let result = MarkdownHugeTablePerformanceResult(
            passed: failures.isEmpty,
            failures: failures,
            rowCount: rowCount,
            documentLength: (workspace.textView.string as NSString).length,
            loadLatency: loadLatency,
            initialRenderLatency: initialRenderLatency,
            scrollLatencies: scrollLatencies,
            scrollRenderLatencies: scrollRenderLatencies,
            averageEditLatency: editResult.averageLatency,
            maximumEditLatency: editResult.maximumLatency,
            residentMemoryBeforeLoad: residentMemoryBeforeLoad,
            residentMemoryAfterLoad: residentMemoryAfterLoad,
            residentMemoryAfterInteractions: residentMemoryAfterInteractions,
            sourcePreserved: sourcePreserved,
            searchPreserved: searchPreserved,
            copyPreserved: copyPasteResult.copyPreserved,
            pastePreserved: copyPasteResult.pastePreserved
        )
        writeSummary(result, to: evidenceDirectory)
        return result
    }

    public static func runCLI(evidenceDirectory: URL? = nil) -> Int32 {
        let result = verify(evidenceDirectory: evidenceDirectory)
        let sortedScrollLatencies = result.scrollLatencies.sorted()
        let p95 = percentile(sortedScrollLatencies, percentile: 0.95)
        let maximumScroll = sortedScrollLatencies.last ?? 0
        let sortedScrollRenderLatencies = result.scrollRenderLatencies.sorted()
        let p95ScrollRender = percentile(sortedScrollRenderLatencies, percentile: 0.95)
        let maximumScrollRender = sortedScrollRenderLatencies.last ?? 0
        let memoryGrowth =
            result.residentMemoryAfterInteractions > result.residentMemoryBeforeLoad
            ? result.residentMemoryAfterInteractions - result.residentMemoryBeforeLoad
            : 0
        let summary = String(
            format:
                "%d rows/%d chars, load %.1f ms, first %.1f ms, scroll update p95/max %.1f/%.1f ms, raster p95/max %.1f/%.1f ms, edit avg/max %.1f/%.1f ms, memory +%.1f MiB",
            result.rowCount,
            result.documentLength,
            result.loadLatency * 1_000,
            result.initialRenderLatency * 1_000,
            p95 * 1_000,
            maximumScroll * 1_000,
            p95ScrollRender * 1_000,
            maximumScrollRender * 1_000,
            result.averageEditLatency * 1_000,
            result.maximumEditLatency * 1_000,
            mebibytes(memoryGrowth)
        )

        if result.passed {
            // pitchai-allow-cli-output: this explicit verifier CLI edge reports its result.
            print("huge-table-performance-verifier: PASS (\(summary))")
            return 0
        }

        // pitchai-allow-cli-output: this explicit verifier CLI edge reports its result.
        print("huge-table-performance-verifier: FAIL (\(summary))")
        for failure in result.failures {
            // pitchai-allow-cli-output: this explicit verifier CLI edge reports failures.
            print("- \(failure)")
        }
        return 1
    }

    private struct EditResult {
        let averageLatency: TimeInterval
        let maximumLatency: TimeInterval
        let expectedSource: String
    }

    private struct ScrollMeasurements {
        let updateLatencies: [TimeInterval]
        let renderLatencies: [TimeInterval]
    }

    private struct CopyPasteResult {
        let copyPreserved: Bool
        let pastePreserved: Bool
        let expectedSource: String
    }

    private static func measureScrollFrames(
        _ workspace: EditorWorkspaceView,
        bitmap: NSBitmapImageRep
    ) -> ScrollMeasurements {
        let ratios: [CGFloat] = [
            0.08, 0.24, 0.42, 0.61, 0.79, 0.96,
            0.82, 0.64, 0.45, 0.27, 0.10,
            0.35, 0.58, 0.88, 0.50,
        ]
        let clipView = workspace.scrollView.contentView
        let maximumY = max(0, workspace.textView.frame.height - clipView.bounds.height)

        var updateLatencies: [TimeInterval] = []
        var renderLatencies: [TimeInterval] = []
        updateLatencies.reserveCapacity(ratios.count)
        renderLatencies.reserveCapacity(ratios.count)

        for ratio in ratios {
            let start = CFAbsoluteTimeGetCurrent()
            clipView.scroll(to: NSPoint(x: 0, y: maximumY * ratio))
            workspace.scrollView.reflectScrolledClipView(clipView)
            workspace.layoutSubtreeIfNeeded()
            updateLatencies.append(CFAbsoluteTimeGetCurrent() - start)

            workspace.needsDisplay = true
            workspace.textView.needsDisplay = true
            let renderStart = CFAbsoluteTimeGetCurrent()
            workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
            renderLatencies.append(CFAbsoluteTimeGetCurrent() - renderStart)
        }

        return ScrollMeasurements(
            updateLatencies: updateLatencies,
            renderLatencies: renderLatencies
        )
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
            guard
                workspace.textView.shouldChangeText(
                    in: editRange,
                    replacementString: replacement
                )
            else {
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

    private static func verifyCopyPaste(
        _ workspace: EditorWorkspaceView,
        rowCount: Int,
        expectedSource: String
    ) -> CopyPasteResult {
        let copiedText = "Search preservation sentinel row \(rowCount - 9)"
        let source = workspace.textView.string as NSString
        let copyRange = source.range(of: copiedText)
        let editNeedle = "editable-value-\(rowCount / 2)-typing-marker-"
        let editTarget = source.range(of: editNeedle)
        precondition(copyRange.location != NSNotFound, "missing huge-table copy target")
        precondition(editTarget.location != NSNotFound, "missing huge-table paste target")

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let plainTextType = NSPasteboard.PasteboardType("NSStringPboardType")
        pasteboard.declareTypes([plainTextType], owner: nil)

        workspace.textView.setSelectedRange(copyRange)
        let copied = workspace.textView.writeSelection(
            to: pasteboard,
            type: plainTextType
        )
        let copyPreserved = copied && pasteboard.string(forType: plainTextType) == copiedText

        let insertionRange = NSRange(location: NSMaxRange(editTarget) + 1, length: 0)
        workspace.textView.setSelectedRange(insertionRange)
        let pasted = workspace.textView.readSelection(
            from: pasteboard,
            type: plainTextType
        )
        let expectedAfterPaste = (expectedSource as NSString).replacingCharacters(
            in: insertionRange,
            with: copiedText
        )
        let pastePreserved = pasted && workspace.textView.string == expectedAfterPaste

        return CopyPasteResult(
            copyPreserved: copyPreserved,
            pastePreserved: pastePreserved,
            expectedSource: expectedAfterPaste
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
            let editValue =
                row == rowCount / 2
                ? "editable-value-\(row)-typing-marker-X"
                : "stable-value-\(row)"
            let searchValue =
                row == rowCount - 9
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
        let sortedRenderLatencies = result.scrollRenderLatencies.sorted()
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
                $0 > scrollUpdateBudget
            }.count,
            "scrollRasterMilliseconds": result.scrollRenderLatencies.map { $0 * 1_000 },
            "scrollRasterP95Milliseconds": percentile(
                sortedRenderLatencies,
                percentile: 0.95
            ) * 1_000,
            "scrollRasterMaximumMilliseconds": (sortedRenderLatencies.last ?? 0) * 1_000,
            "averageEditMilliseconds": result.averageEditLatency * 1_000,
            "maximumEditMilliseconds": result.maximumEditLatency * 1_000,
            "residentMemoryBeforeLoadBytes": result.residentMemoryBeforeLoad,
            "residentMemoryAfterLoadBytes": result.residentMemoryAfterLoad,
            "residentMemoryAfterInteractionsBytes": result.residentMemoryAfterInteractions,
            "sourcePreserved": result.sourcePreserved,
            "searchPreserved": result.searchPreserved,
            "copyPreserved": result.copyPreserved,
            "pastePreserved": result.pastePreserved,
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
