import AppKit
import AvivCore
import CryptoKit
import Foundation

@MainActor
enum StyledMarkerRevealVerifier {
    static func runCLI(arguments: [String]) async -> Int32 {
        do {
            let options = try Options(arguments: arguments)
            try FileManager.default.createDirectory(
                at: options.evidenceDirectory,
                withIntermediateDirectories: true
            )

            let controller = DocumentWindowController()
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            guard controller.open(url: options.localFile) else {
                throw VerificationError("Aviv could not open the local Markdown document.")
            }
            let local = try await verifyRealClickReveal(
                controller: controller,
                sourceKind: "local",
                sourceURL: options.localFile,
                evidenceDirectory: options.evidenceDirectory
            )
            emit(
                "AVIV_STYLED_REVEAL_LOCAL marker=\(local.headingMarker) click=true focused_delta=\(local.readingToFocusedPixelDifference) restored_delta=\(local.readingToRestoredPixelDifference)"
            )

            guard await controller.openRemote(url: options.remoteURL) else {
                throw VerificationError("Aviv could not open the live URL-backed Markdown document.")
            }
            guard controller.representedRemoteSource != nil,
                controller.liveDocumentIndicatorFrameForTesting != nil
            else {
                throw VerificationError("The URL-backed document lost its live-source state.")
            }
            let remote = try await verifyRealClickReveal(
                controller: controller,
                sourceKind: "remote",
                sourceURL: options.remoteURL,
                evidenceDirectory: options.evidenceDirectory
            )
            emit(
                "AVIV_STYLED_REVEAL_REMOTE marker=\(remote.headingMarker) click=true focused_delta=\(remote.readingToFocusedPixelDifference) restored_delta=\(remote.readingToRestoredPixelDifference) live_indicator=true"
            )

            let report = VerificationReport(local: local, remote: remote)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(
                to: options.evidenceDirectory.appendingPathComponent(
                    "styled-marker-reveal-result.json"
                ),
                options: .atomic
            )

            controller.stopRemoteSync()
            controller.close()
            emit("styled-marker-reveal-verifier: PASS")
            return 0
        } catch {
            fputs("styled-marker-reveal-verifier: FAIL: \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            return 1
        }
    }

    private static func verifyRealClickReveal(
        controller: DocumentWindowController,
        sourceKind: String,
        sourceURL: URL,
        evidenceDirectory: URL
    ) async throws -> SourceResult {
        guard let window = controller.window else {
            throw VerificationError("The \(sourceKind) document window is missing.")
        }
        window.setContentSize(NSSize(width: 1080, height: 760))
        try await settle(controller)

        let workspace = controller.workspace
        let markdown = workspace.textView.string
        let targets = try revealTargets(in: markdown)
        workspace.textView.scrollRangeToVisible(targets.headingBody)
        try await settle(controller)

        try await click(
            characterRange: targets.clickAway,
            in: workspace.textView,
            window: window
        )
        try assertSelection(
            workspace.textView.selectedRange(),
            isInside: targets.clickAway,
            label: "reading-mode click-away"
        )
        guard headingMarkers(in: workspace, matching: targets).isEmpty else {
            throw VerificationError(
                "The \(sourceKind) heading marker remained painted in reading mode."
            )
        }
        let readingHeadingFrame = try frame(
            for: targets.headingBody,
            in: workspace.textView,
            targetView: workspace
        )
        let readingEvidence = try captureRenderedEvidence(
            from: workspace,
            documentURL: sourceURL,
            selection: targets.clickAway,
            targets: targets,
            to: evidenceDirectory.appendingPathComponent("\(sourceKind)-reading.png")
        )
        let readingOrigin = workspace.scrollView.contentView.bounds.origin

        try await click(
            characterRange: targets.headingBody,
            in: workspace.textView,
            window: window
        )
        try assertSelection(
            workspace.textView.selectedRange(),
            isInside: targets.headingBody,
            label: "focused heading click"
        )
        let liveFocusedMarkers = headingMarkers(in: workspace, matching: targets)
        guard liveFocusedMarkers.map(\.token.label) == [targets.headingMarker] else {
            throw VerificationError(
                "The real \(sourceKind) click mounted \(liveFocusedMarkers.map(\.token.label)) instead of the raw \(targets.headingMarker) heading marker."
            )
        }
        let focusedHeadingFrame = try frame(
            for: targets.headingBody,
            in: workspace.textView,
            targetView: workspace
        )
        let focusedEvidence = try captureRenderedEvidence(
            from: workspace,
            documentURL: sourceURL,
            selection: targets.headingBody,
            targets: targets,
            to: evidenceDirectory.appendingPathComponent(
                "\(sourceKind)-focused-heading.png"
            )
        )
        try captureNativeHeader(
            window,
            to: evidenceDirectory.appendingPathComponent(
                "\(sourceKind)-native-header.png"
            )
        )
        let focusedOrigin = workspace.scrollView.contentView.bounds.origin

        try await click(
            characterRange: targets.clickAway,
            in: workspace.textView,
            window: window
        )
        try assertSelection(
            workspace.textView.selectedRange(),
            isInside: targets.clickAway,
            label: "restored click-away"
        )
        guard headingMarkers(in: workspace, matching: targets).isEmpty else {
            throw VerificationError(
                "The \(sourceKind) heading marker remained mounted after clicking away."
            )
        }
        let restoredHeadingFrame = try frame(
            for: targets.headingBody,
            in: workspace.textView,
            targetView: workspace
        )
        let restoredEvidence = try captureRenderedEvidence(
            from: workspace,
            documentURL: sourceURL,
            selection: targets.clickAway,
            targets: targets,
            to: evidenceDirectory.appendingPathComponent("\(sourceKind)-restored.png")
        )
        let restoredOrigin = workspace.scrollView.contentView.bounds.origin

        let markerRegion = union(of: focusedEvidence.markerFrames).insetBy(dx: -3, dy: -3)
        let focusedDifference = pixelDifference(
            readingEvidence.snapshot,
            focusedEvidence.snapshot,
            in: markerRegion,
            viewBounds: workspace.bounds
        )
        let restoredDifference = pixelDifference(
            readingEvidence.snapshot,
            restoredEvidence.snapshot,
            in: markerRegion,
            viewBounds: workspace.bounds
        )
        let focusedGeometryDelta = rectDelta(readingHeadingFrame, focusedHeadingFrame)
        let restoredGeometryDelta = rectDelta(readingHeadingFrame, restoredHeadingFrame)
        let focusedScrollDelta = pointDelta(readingOrigin, focusedOrigin)
        let restoredScrollDelta = pointDelta(readingOrigin, restoredOrigin)

        guard focusedDifference > 0 else {
            throw VerificationError(
                "A real click on the \(sourceKind) heading painted no raw \(targets.headingMarker) marker."
            )
        }
        guard restoredDifference == 0 else {
            throw VerificationError(
                "The \(sourceKind) heading did not return exactly to reading mode (\(restoredDifference) changed pixel bytes)."
            )
        }
        guard focusedGeometryDelta <= 0.01, restoredGeometryDelta <= 0.01 else {
            throw VerificationError(
                "The \(sourceKind) heading geometry moved during reveal or restoration."
            )
        }
        guard focusedScrollDelta <= 0.01, restoredScrollDelta <= 0.01 else {
            throw VerificationError(
                "The \(sourceKind) viewport moved during reveal or restoration."
            )
        }
        guard workspace.textView.string == markdown else {
            throw VerificationError("Clicking the \(sourceKind) heading changed Markdown source.")
        }
        guard controller.documentTitleTextForTesting == sourceURL.lastPathComponent else {
            throw VerificationError("The \(sourceKind) document title changed during interaction.")
        }

        return SourceResult(
            sourceKind: sourceKind,
            sourceURL: sourceURL.absoluteString,
            documentTitle: controller.documentTitleTextForTesting,
            headingMarker: targets.headingMarker,
            headingBody: (markdown as NSString).substring(with: targets.headingBody),
            markdownSHA256: SHA256.hash(data: Data(markdown.utf8)).map {
                String(format: "%02x", $0)
            }.joined(),
            focusedSelectionLocation: targets.headingBody.location,
            readingToFocusedPixelDifference: focusedDifference,
            readingToRestoredPixelDifference: restoredDifference,
            focusedGeometryDelta: focusedGeometryDelta,
            restoredGeometryDelta: restoredGeometryDelta,
            focusedScrollDelta: focusedScrollDelta,
            restoredScrollDelta: restoredScrollDelta,
            sourcePreserved: true,
            liveIndicatorPresent: sourceKind == "remote"
                ? controller.liveDocumentIndicatorFrameForTesting != nil : false
        )
    }

    private static func click(
        characterRange: NSRange,
        in textView: NSTextView,
        window: NSWindow
    ) async throws {
        window.makeFirstResponder(textView)
        guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            throw VerificationError("The text layout is unavailable for real click synthesis.")
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterRange.location, length: 1),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        let pointInWindow = textView.convert(
            NSPoint(x: rect.midX, y: rect.midY),
            to: nil
        )
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard
            let mouseDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ),
            let mouseUp = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: timestamp + 0.01,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        else {
            throw VerificationError("Could not construct the AppKit click events.")
        }
        NSApplication.shared.postEvent(mouseDown, atStart: false)
        NSApplication.shared.postEvent(mouseUp, atStart: false)
        for _ in 0..<40 where !selectionIsInside(
            textView.selectedRange(),
            target: characterRange
        ) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard selectionIsInside(textView.selectedRange(), target: characterRange) else {
            throw VerificationError(
                "The native click event was dispatched but did not move the caret into \(characterRange.location):\(characterRange.length)."
            )
        }
        try await settleWindow(window)
    }

    private static func revealTargets(in markdown: String) throws -> RevealTargets {
        let nsString = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let headingRegex = try NSRegularExpression(
            pattern: #"^(#{1,6})\s+(.+)$"#,
            options: [.anchorsMatchLines]
        )
        guard let heading = headingRegex.firstMatch(in: markdown, range: fullRange) else {
            throw VerificationError("The document has no ATX heading to click.")
        }
        let headingMarkerRange = heading.range(at: 1)
        let headingBodyRange = heading.range(at: 2)

        var clickAway: NSRange?
        var index = NSMaxRange(nsString.lineRange(for: heading.range))
        while index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let line = nsString.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty,
                !line.hasPrefix("#"),
                !line.hasPrefix("|")
            {
                let candidate = nsString.range(
                    of: line,
                    options: [],
                    range: lineRange
                )
                if candidate.location != NSNotFound {
                    clickAway = candidate
                    break
                }
            }
            index = NSMaxRange(lineRange)
        }
        guard let clickAway else {
            throw VerificationError("The document has no visible click-away line after its heading.")
        }

        return RevealTargets(
            headingMarker: nsString.substring(with: headingMarkerRange),
            headingMarkerRange: headingMarkerRange,
            headingBody: headingBodyRange,
            clickAway: clickAway
        )
    }

    private static func assertSelection(
        _ selection: NSRange,
        isInside target: NSRange,
        label: String
    ) throws {
        guard selectionIsInside(selection, target: target) else {
            throw VerificationError(
                "The \(label) event did not move the caret into its target (caret=\(selection.location), target=\(target.location):\(target.length))."
            )
        }
    }

    private static func selectionIsInside(_ selection: NSRange, target: NSRange) -> Bool {
        selection.length == 0
            && (
                NSLocationInRange(selection.location, target)
                    || selection.location == NSMaxRange(target)
            )
    }

    private static func headingMarkers(
        in workspace: EditorWorkspaceView,
        matching targets: RevealTargets
    ) -> [(token: MarkdownAnnotationToken, frame: NSRect)] {
        workspace.styledMarkerFramesForTesting.filter {
            $0.token.role == .heading && $0.token.range == targets.headingMarkerRange
        }
    }

    private static func settle(_ controller: DocumentWindowController) async throws {
        controller.workspace.layoutSubtreeIfNeeded()
        try await settleWindow(controller.window)
        controller.workspace.layoutSubtreeIfNeeded()
        controller.workspace.displayIfNeeded()
    }

    private static func settleWindow(_ window: NSWindow?) async throws {
        guard let window else {
            throw VerificationError("The verifier window is unavailable.")
        }
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 120_000_000)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.superview?.displayIfNeeded()
    }

    private static func captureRenderedEvidence(
        from liveWorkspace: EditorWorkspaceView,
        documentURL: URL,
        selection: NSRange,
        targets: RevealTargets,
        to url: URL
    ) throws -> RenderedEvidence {
        let workspace = EditorWorkspaceView(frame: liveWorkspace.bounds)
        workspace.documentFormat = liveWorkspace.documentFormat
        workspace.loadMarkdown(liveWorkspace.textView.string)
        workspace.updateDocumentTitle(url: documentURL, isEdited: false)
        workspace.textView.setSelectedRange(
            NSRange(location: selection.location, length: 0)
        )
        workspace.layoutSubtreeIfNeeded()
        workspace.needsDisplay = true
        workspace.textView.needsDisplay = true
        workspace.displayIfNeeded()
        let markerFrames = headingMarkers(in: workspace, matching: targets).map(\.frame)
        if selection.location == targets.headingBody.location,
            markerFrames.isEmpty
        {
            throw VerificationError("The evidence view did not paint the focused heading marker.")
        }
        guard let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) else {
            throw VerificationError("Could not allocate a workspace evidence bitmap.")
        }
        bitmap.size = workspace.bounds.size
        workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
        guard let pointer = bitmap.bitmapData,
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw VerificationError("Could not encode a workspace evidence bitmap.")
        }
        try png.write(to: url, options: .atomic)
        return RenderedEvidence(
            snapshot: Snapshot(
                data: Data(bytes: pointer, count: bitmap.bytesPerRow * bitmap.pixelsHigh),
                pixelsWide: bitmap.pixelsWide,
                pixelsHigh: bitmap.pixelsHigh,
                bytesPerRow: bitmap.bytesPerRow,
                bytesPerPixel: max(1, bitmap.bitsPerPixel / 8)
            ),
            markerFrames: markerFrames
        )
    }

    private static func captureNativeHeader(_ window: NSWindow, to url: URL) throws {
        guard let frameView = window.contentView?.superview else {
            throw VerificationError("The native window frame is unavailable for evidence.")
        }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        let captureBounds = NSRect(
            x: frameView.bounds.minX,
            y: frameView.bounds.maxY - min(48, frameView.bounds.height),
            width: frameView.bounds.width,
            height: min(48, frameView.bounds.height)
        )
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: captureBounds) else {
            throw VerificationError("Could not allocate a native-window evidence bitmap.")
        }
        bitmap.size = captureBounds.size
        frameView.cacheDisplay(in: captureBounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw VerificationError("Could not encode native-window evidence.")
        }
        try png.write(to: url, options: .atomic)
    }

    private static func frame(
        for characterRange: NSRange,
        in textView: NSTextView,
        targetView: NSView
    ) throws -> NSRect {
        guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            throw VerificationError("The text layout is unavailable.")
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return textView.convert(rect, to: targetView)
    }

    private static func pixelDifference(
        _ lhs: Snapshot,
        _ rhs: Snapshot,
        in region: NSRect,
        viewBounds: NSRect
    ) -> Int {
        precondition(lhs.pixelsWide == rhs.pixelsWide)
        precondition(lhs.pixelsHigh == rhs.pixelsHigh)
        precondition(lhs.bytesPerRow == rhs.bytesPerRow)
        precondition(lhs.bytesPerPixel == rhs.bytesPerPixel)

        let xScale = CGFloat(lhs.pixelsWide) / viewBounds.width
        let yScale = CGFloat(lhs.pixelsHigh) / viewBounds.height
        let minimumX = max(0, Int(floor(region.minX * xScale)))
        let maximumX = min(lhs.pixelsWide, Int(ceil(region.maxX * xScale)))
        let directMinimumY = max(0, Int(floor(region.minY * yScale)))
        let directMaximumY = min(lhs.pixelsHigh, Int(ceil(region.maxY * yScale)))
        let mirroredMinimumY = max(0, lhs.pixelsHigh - directMaximumY)
        let mirroredMaximumY = min(lhs.pixelsHigh, lhs.pixelsHigh - directMinimumY)
        return max(
            pixelDifference(
                lhs,
                rhs,
                minimumX: minimumX,
                maximumX: maximumX,
                minimumY: directMinimumY,
                maximumY: directMaximumY
            ),
            pixelDifference(
                lhs,
                rhs,
                minimumX: minimumX,
                maximumX: maximumX,
                minimumY: mirroredMinimumY,
                maximumY: mirroredMaximumY
            )
        )
    }

    private static func pixelDifference(
        _ lhs: Snapshot,
        _ rhs: Snapshot,
        minimumX: Int,
        maximumX: Int,
        minimumY: Int,
        maximumY: Int
    ) -> Int {
        guard minimumX < maximumX, minimumY < maximumY else { return 0 }
        var difference = 0
        lhs.data.withUnsafeBytes { lhsBytes in
            rhs.data.withUnsafeBytes { rhsBytes in
                guard let lhsBase = lhsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    let rhsBase = rhsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else { return }
                for y in minimumY..<maximumY {
                    let row = y * lhs.bytesPerRow
                    for x in minimumX..<maximumX {
                        let pixel = row + (x * lhs.bytesPerPixel)
                        for channel in 0..<lhs.bytesPerPixel
                        where lhsBase[pixel + channel] != rhsBase[pixel + channel] {
                            difference += 1
                        }
                    }
                }
            }
        }
        return difference
    }

    private static func rectDelta(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        max(
            abs(lhs.minX - rhs.minX),
            abs(lhs.minY - rhs.minY),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height)
        )
    }

    private static func pointDelta(_ lhs: NSPoint, _ rhs: NSPoint) -> CGFloat {
        max(abs(lhs.x - rhs.x), abs(lhs.y - rhs.y))
    }

    private static func union(of rects: [NSRect]) -> NSRect {
        rects.reduce(NSRect.null) { $0.union($1) }
    }

    private static func emit(_ message: String) {
        fputs("\(message)\n", stdout)
        fflush(stdout)
    }

    private struct Options {
        let remoteURL: URL
        let localFile: URL
        let evidenceDirectory: URL

        init(arguments: [String]) throws {
            guard let verifierIndex = arguments.firstIndex(of: "--verify-styled-marker-reveal"),
                arguments.indices.contains(verifierIndex + 1),
                let remoteURL = URL(string: arguments[verifierIndex + 1]),
                RemoteMarkdownSource.isAllowedRemoteURL(remoteURL),
                let localIndex = arguments.firstIndex(of: "--local-file"),
                arguments.indices.contains(localIndex + 1),
                let evidenceIndex = arguments.firstIndex(of: "--evidence-dir"),
                arguments.indices.contains(evidenceIndex + 1)
            else {
                throw VerificationError(
                    "Usage: Aviv --verify-styled-marker-reveal HTTPS_URL --local-file PATH --evidence-dir PATH"
                )
            }
            let localFile = URL(fileURLWithPath: arguments[localIndex + 1])
            guard FileManager.default.fileExists(atPath: localFile.path) else {
                throw VerificationError("The local Markdown document does not exist.")
            }
            self.remoteURL = remoteURL
            self.localFile = localFile
            self.evidenceDirectory = URL(fileURLWithPath: arguments[evidenceIndex + 1])
        }
    }

    private struct RevealTargets {
        let headingMarker: String
        let headingMarkerRange: NSRange
        let headingBody: NSRange
        let clickAway: NSRange
    }

    private struct RenderedEvidence {
        let snapshot: Snapshot
        let markerFrames: [NSRect]
    }

    private struct Snapshot {
        let data: Data
        let pixelsWide: Int
        let pixelsHigh: Int
        let bytesPerRow: Int
        let bytesPerPixel: Int
    }

    private struct VerificationReport: Encodable {
        let local: SourceResult
        let remote: SourceResult
    }

    private struct SourceResult: Encodable {
        let sourceKind: String
        let sourceURL: String
        let documentTitle: String
        let headingMarker: String
        let headingBody: String
        let markdownSHA256: String
        let focusedSelectionLocation: Int
        let readingToFocusedPixelDifference: Int
        let readingToRestoredPixelDifference: Int
        let focusedGeometryDelta: CGFloat
        let restoredGeometryDelta: CGFloat
        let focusedScrollDelta: CGFloat
        let restoredScrollDelta: CGFloat
        let sourcePreserved: Bool
        let liveIndicatorPresent: Bool
    }
}

private struct VerificationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
