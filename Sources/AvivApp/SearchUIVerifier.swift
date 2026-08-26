import AppKit
import AvivCore
import Foundation

@MainActor
enum SearchUIVerifier {
    private static let widths: [CGFloat] = [720, 840, 1_080, 1_440]

    static func runCLI(arguments: [String]) async -> Int32 {
        do {
            let options = try Options(arguments: arguments)
            try FileManager.default.createDirectory(
                at: options.evidenceDirectory,
                withIntermediateDirectories: true
            )

            let controller = DocumentWindowController()
            let delegate = AppDelegate(documentController: controller)
            NSApp.delegate = delegate
            delegate.buildMenu()
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            guard controller.open(url: options.fixture) else {
                throw SearchUIVerificationError("Aviv could not open the search fixture.")
            }
            try await settleWindow(controller.window)

            let expectedMatches = MarkdownSearchIndex.findMatches(
                in: controller.workspace.textView.string,
                query: options.query
            )
            guard expectedMatches.count >= 3 else {
                throw SearchUIVerificationError(
                    "The fixture needs at least three search results for navigation verification."
                )
            }

            var widthEvidence: [[String: Any]] = []
            for width in widths {
                let evidence = try await verifySearchLayout(
                    controller: controller,
                    delegate: delegate,
                    width: width,
                    query: options.query,
                    expectedMatches: expectedMatches
                )
                widthEvidence.append(evidence)

                if width == 720 || width == 1_080 {
                    try captureNativeWindow(
                        controller,
                        to: options.evidenceDirectory.appendingPathComponent(
                            "search-native-\(Int(width)).png"
                        )
                    )
                }
                controller.closeDocumentSearchForTesting()
                try await settleWindow(controller.window)
            }

            let liveToolbarEvidence = try await verifyLiveSearchToolbarClearance(
                controller: controller,
                width: 720,
                query: options.query
            )
            try captureNativeWindow(
                controller,
                to: options.evidenceDirectory.appendingPathComponent(
                    "search-native-720-live.png"
                )
            )
            controller.workspace.updateRemoteSyncPresentation(nil)
            controller.closeDocumentSearchForTesting()
            try await settleWindow(controller.window)

            let performance = try verifyLargeDocumentSearchPerformance(query: options.query)
            let report: [String: Any] = [
                "query": options.query,
                "fixture_match_count": expectedMatches.count,
                "large_document_bytes": performance.bytes,
                "large_document_match_count": performance.matches,
                "large_document_search_ms": performance.milliseconds,
                "live_toolbar_720": liveToolbarEvidence,
                "widths": widthEvidence,
            ]
            let reportData = try JSONSerialization.data(
                withJSONObject: report,
                options: [.prettyPrinted, .sortedKeys]
            )
            try reportData.write(
                to: options.evidenceDirectory.appendingPathComponent("search-ui-results.json"),
                options: .atomic
            )

            controller.close()
            emit(
                "AVIV_SEARCH_PERFORMANCE bytes=\(performance.bytes) matches=\(performance.matches) duration_ms=\(String(format: "%.2f", performance.milliseconds))"
            )
            emit("search-ui-verifier: PASS")
            return 0
        } catch {
            fputs("search-ui-verifier: FAIL: \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            return 1
        }
    }

    private static func verifySearchLayout(
        controller: DocumentWindowController,
        delegate: AppDelegate,
        width: CGFloat,
        query: String,
        expectedMatches: [NSRange]
    ) async throws -> [String: Any] {
        guard let window = controller.window else {
            throw SearchUIVerificationError("The document window is unavailable.")
        }
        window.setContentSize(NSSize(width: width, height: 720))
        try await settleWindow(window)
        let geometryBefore = DocumentGeometry(workspace: controller.workspace)

        controller.showDocumentSearchForTesting(query: query)
        try await settleWindow(window)

        guard controller.isDocumentSearchActiveForTesting else {
            throw SearchUIVerificationError("Search did not become active at width \(Int(width)).")
        }
        guard controller.documentSearchQueryForTesting == query else {
            throw SearchUIVerificationError("Search lost the query at width \(Int(width)).")
        }
        guard controller.documentSearchMatchRangesForTesting == expectedMatches else {
            throw SearchUIVerificationError(
                "Search returned inconsistent matches at width \(Int(width))."
            )
        }

        let geometryAfter = DocumentGeometry(workspace: controller.workspace)
        guard geometryBefore.matches(geometryAfter) else {
            throw SearchUIVerificationError(
                "Search changed document geometry at width \(Int(width)): before=\(geometryBefore.summary) after=\(geometryAfter.summary)."
            )
        }

        guard let searchFrame = controller.documentSearchToolbarFrameForTesting,
            searchFrame.width > 300,
            searchFrame.height >= 24
        else {
            throw SearchUIVerificationError(
                "Search did not present a stable toolbar frame at width \(Int(width))."
            )
        }
        let nativeCenterOffset = searchFrame.midX - controller.workspace.bounds.midX
        guard abs(nativeCenterOffset) <= 40 else {
            throw SearchUIVerificationError(
                "Search escaped AppKit's balanced center slot at width \(Int(width)): offset=\(nativeCenterOffset), frame=\(format(searchFrame))."
            )
        }

        let externalToolbarFrames = try toolbarItemFrames(
            excluding: "Aviv.Toolbar.DocumentSearch",
            controller: controller
        )
        let toolbarCollisions = externalToolbarFrames.filter {
            $0.intersects(searchFrame.insetBy(dx: -4, dy: -2))
        }
        guard toolbarCollisions.isEmpty else {
            throw SearchUIVerificationError(
                "Search overlaps toolbar controls at width \(Int(width)): search=\(format(searchFrame)) controls=\(toolbarCollisions.map(format).joined(separator: ";"))."
            )
        }

        let trafficLights = try trafficLightFrame(controller: controller)
        guard !searchFrame.intersects(trafficLights.insetBy(dx: -8, dy: -8)) else {
            throw SearchUIVerificationError(
                "Search overlaps the macOS window controls at width \(Int(width))."
            )
        }

        let controls = controller.documentSearchControlFramesForTesting
        try verifySearchControlGeometry(controls, searchFrame: searchFrame, width: width)

        let activeToolbarIdentifiers = Set(
            window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
        )
        let temporarilyRemovedIdentifiers: Set<String> = [
            "Aviv.Toolbar.DocumentTitle",
            "Aviv.Toolbar.ZoomOut",
            "Aviv.Toolbar.ActualSize",
            "Aviv.Toolbar.ZoomIn",
            "Aviv.Toolbar.Bold",
            "Aviv.Toolbar.Italic",
            "Aviv.Toolbar.Code",
            "Aviv.Toolbar.Heading1",
            "Aviv.Toolbar.Heading2",
        ]
        guard activeToolbarIdentifiers.isDisjoint(with: temporarilyRemovedIdentifiers) else {
            throw SearchUIVerificationError(
                "Search mode did not compact the toolbar at width \(Int(width))."
            )
        }

        let outlineCount = controller.workspace.outlineSearchHitCountForTesting
        let outlineFrames = controller.workspace.outlineSearchHitFramesForTesting
        guard outlineCount >= 4,
            outlineFrames.count == outlineCount,
            outlineFrames.allSatisfy({ !$0.isEmpty })
        else {
            throw SearchUIVerificationError(
                "The outline did not expose stable yellow search sections at width \(Int(width))."
            )
        }
        let outlineIdentifiers = controller.workspace.outlineSearchHitIdentifiersForTesting
        guard outlineIdentifiers.contains(where: { $0.contains("heading") }),
            outlineIdentifiers.contains(where: { $0.contains("table") })
        else {
            throw SearchUIVerificationError(
                "Search hits were not mapped to both heading sections and direct structure rows."
            )
        }

        try verifyButtonAndShortcutNavigation(controller: controller, delegate: delegate)
        let searchFrameAfterNavigation = try requireSearchFrame(controller)
        guard searchFrameAfterNavigation.equalTo(searchFrame) else {
            throw SearchUIVerificationError(
                "The search toolbar shifted while its result counter changed at width \(Int(width))."
            )
        }

        emit(
            "AVIV_SEARCH_LAYOUT width=\(Int(width)) center_offset=\(Int(nativeCenterOffset)) overlap=false controls=5 matches=\(expectedMatches.count) outline_sections=\(outlineCount) geometry_stable=true"
        )
        return [
            "width": Int(width),
            "search_frame": format(searchFrame),
            "native_center_offset": nativeCenterOffset,
            "toolbar_control_frames": externalToolbarFrames.map(format),
            "match_count": expectedMatches.count,
            "outline_section_count": outlineCount,
            "outline_identifiers": outlineIdentifiers,
            "geometry_stable": true,
            "overlap": false,
        ]
    }

    private static func verifyLiveSearchToolbarClearance(
        controller: DocumentWindowController,
        width: CGFloat,
        query: String
    ) async throws -> [String: Any] {
        guard let window = controller.window else {
            throw SearchUIVerificationError("The document window is unavailable.")
        }
        window.setContentSize(NSSize(width: width, height: 720))
        try await settleWindow(window)
        let geometryBefore = DocumentGeometry(workspace: controller.workspace)

        controller.showDocumentSearchForTesting(query: query)
        controller.workspace.updateRemoteSyncPresentation(
            RemoteSyncPresentation(
                phase: .watching,
                sourceHost: "proof.pitchai.net",
                isWritable: true,
                detail: "Search toolbar clearance proof"
            )
        )
        try await settleWindow(window)

        let geometryAfter = DocumentGeometry(workspace: controller.workspace)
        guard geometryBefore.matches(geometryAfter) else {
            throw SearchUIVerificationError(
                "Search plus the live-document badge changed document geometry at width 720."
            )
        }
        guard let searchFrame = controller.documentSearchToolbarFrameForTesting,
            let liveFrame = controller.liveDocumentIndicatorFrameForTesting
        else {
            throw SearchUIVerificationError(
                "Search or the live-document badge disappeared at width 720."
            )
        }
        let externalFrames = try toolbarItemFrames(
            excluding: "Aviv.Toolbar.DocumentSearch",
            controller: controller
        )
        guard externalFrames.count == 4 else {
            throw SearchUIVerificationError(
                "The compact live-search toolbar did not preserve all four primary controls."
            )
        }
        guard
            externalFrames.allSatisfy({
                !$0.intersects(searchFrame.insetBy(dx: -4, dy: -2))
            }), !liveFrame.intersects(searchFrame.insetBy(dx: -4, dy: -2))
        else {
            throw SearchUIVerificationError(
                "Search overlaps a primary or live-document toolbar control at width 720."
            )
        }

        emit(
            "AVIV_SEARCH_LIVE_LAYOUT width=720 overlap=false primary_controls=4 geometry_stable=true"
        )
        return [
            "width": Int(width),
            "search_frame": format(searchFrame),
            "live_badge_frame": format(liveFrame),
            "toolbar_control_frames": externalFrames.map(format),
            "geometry_stable": true,
            "overlap": false,
        ]
    }

    private static func verifySearchControlGeometry(
        _ controls: [String: NSRect],
        searchFrame: NSRect,
        width: CGFloat
    ) throws {
        let required = ["field", "previous", "next", "status", "close"]
        guard Set(controls.keys) == Set(required),
            let field = controls["field"],
            let previous = controls["previous"],
            let next = controls["next"],
            let status = controls["status"],
            let close = controls["close"]
        else {
            throw SearchUIVerificationError("Search is missing one or more fixed controls.")
        }
        let orderedControls = [field, previous, next, status, close]
        for (name, frame) in zip(required, orderedControls) {
            guard searchFrame.insetBy(dx: -1, dy: -1).contains(frame) else {
                throw SearchUIVerificationError(
                    "Search control \(name) escapes its toolbar item at width \(Int(width)): control=\(format(frame)) search=\(format(searchFrame))."
                )
            }
        }
        for leftIndex in required.indices {
            for rightIndex in required.indices where rightIndex > leftIndex {
                let left = orderedControls[leftIndex]
                let right = orderedControls[rightIndex]
                guard !left.intersects(right) else {
                    throw SearchUIVerificationError(
                        "Search controls \(required[leftIndex]) and \(required[rightIndex]) overlap at width \(Int(width))."
                    )
                }
            }
        }

        guard previous.width <= 24,
            next.width <= 24,
            previous.minX - field.maxX <= 4.5,
            next.minX - previous.maxX <= 1.5
        else {
            throw SearchUIVerificationError(
                "Previous/next controls are not tiny and directly attached to search at width \(Int(width))."
            )
        }
    }

    private static func verifyButtonAndShortcutNavigation(
        controller: DocumentWindowController,
        delegate: AppDelegate
    ) throws {
        let count = controller.documentSearchMatchRangesForTesting.count
        guard count >= 3,
            let initial = controller.currentDocumentSearchResultIndexForTesting
        else {
            throw SearchUIVerificationError("Search has too few results for navigation.")
        }

        controller.showNextDocumentSearchResultForTesting()
        guard controller.currentDocumentSearchResultIndexForTesting == (initial + 1) % count else {
            throw SearchUIVerificationError("The attached next-result button did not advance.")
        }
        controller.showPreviousDocumentSearchResultForTesting()
        guard controller.currentDocumentSearchResultIndexForTesting == initial else {
            throw SearchUIVerificationError("The attached previous-result button did not return.")
        }

        let nextItem = try menuItem(identifier: "findNext")
        let previousItem = try menuItem(identifier: "findPrevious")
        guard nextItem.keyEquivalent == "g",
            nextItem.keyEquivalentModifierMask.contains(.command),
            previousItem.keyEquivalent == "G",
            previousItem.keyEquivalentModifierMask.contains([.command, .shift])
        else {
            throw SearchUIVerificationError("Previous/next search shortcuts are not installed.")
        }

        delegate.performDocumentFindAction(nextItem)
        guard controller.currentDocumentSearchResultIndexForTesting == (initial + 1) % count else {
            throw SearchUIVerificationError("Command-G did not advance through the active search.")
        }
        delegate.performDocumentFindAction(previousItem)
        guard controller.currentDocumentSearchResultIndexForTesting == initial else {
            throw SearchUIVerificationError(
                "Command-Shift-G did not return to the previous search result."
            )
        }

        controller.showPreviousDocumentSearchResultForTesting()
        guard controller.currentDocumentSearchResultIndexForTesting == (initial - 1 + count) % count
        else {
            throw SearchUIVerificationError("Previous-result navigation did not wrap.")
        }
        controller.showNextDocumentSearchResultForTesting()
        guard controller.currentDocumentSearchResultIndexForTesting == initial else {
            throw SearchUIVerificationError("Next-result navigation did not wrap back.")
        }
    }

    private static func menuItem(identifier: String) throws -> NSMenuItem {
        func descendants(of items: [NSMenuItem]) -> [NSMenuItem] {
            items.flatMap { item in
                [item] + descendants(of: item.submenu?.items ?? [])
            }
        }
        guard let menu = NSApp.mainMenu,
            let item = descendants(of: menu.items).first(where: {
                $0.identifier?.rawValue == identifier
            })
        else {
            throw SearchUIVerificationError("The \(identifier) menu command is missing.")
        }
        return item
    }

    private static func toolbarItemFrames(
        excluding excludedIdentifier: String,
        controller: DocumentWindowController
    ) throws -> [NSRect] {
        guard let toolbar = controller.window?.toolbar else {
            throw SearchUIVerificationError("The native toolbar is unavailable.")
        }
        return toolbar.items.compactMap { item in
            guard item.itemIdentifier.rawValue != excludedIdentifier,
                let view = item.view,
                !view.isHidden,
                view.alphaValue > 0
            else { return nil }
            return controller.workspace.convert(view.bounds, from: view)
        }.filter { !$0.isEmpty }
    }

    private static func trafficLightFrame(controller: DocumentWindowController) throws -> NSRect {
        guard let window = controller.window else {
            throw SearchUIVerificationError("The document window is unavailable.")
        }
        let frames = [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ].compactMap { window.standardWindowButton($0) }.map { button in
            controller.workspace.convert(button.bounds, from: button)
        }
        guard frames.count == 3 else {
            throw SearchUIVerificationError("The macOS window controls are unavailable.")
        }
        return frames.reduce(NSRect.null) { $0.union($1) }
    }

    private static func requireSearchFrame(_ controller: DocumentWindowController) throws -> NSRect
    {
        guard let frame = controller.documentSearchToolbarFrameForTesting else {
            throw SearchUIVerificationError("Search disappeared during navigation.")
        }
        return frame
    }

    private static func captureNativeWindow(
        _ controller: DocumentWindowController,
        to url: URL
    ) throws {
        guard let window = controller.window else {
            throw SearchUIVerificationError("The native window frame is unavailable for capture.")
        }
        window.orderFrontRegardless()
        window.contentView?.superview?.displayIfNeeded()
        guard
            let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            throw SearchUIVerificationError(
                "The macOS compositor could not capture the search evidence window."
            )
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SearchUIVerificationError("Could not encode the search evidence PNG.")
        }
        try png.write(to: url, options: .atomic)
    }

    private static func verifyLargeDocumentSearchPerformance(
        query: String
    ) throws -> (bytes: Int, matches: Int, milliseconds: Double) {
        let paragraph =
            "## Search performance section\n\nThe toolbar keeps search-target responsive while preserving document geometry and outline metadata.\n\n"
        let markdown = String(repeating: paragraph, count: 16_000)
        let start = ProcessInfo.processInfo.systemUptime
        let index = MarkdownSearchIndex(markdown: markdown, query: query)
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        guard index.matchRanges.count == 16_000 else {
            throw SearchUIVerificationError(
                "Large-document search returned \(index.matchRanges.count) matches, expected 16000."
            )
        }
        guard milliseconds <= 350 else {
            throw SearchUIVerificationError(
                "Large-document search took \(String(format: "%.2f", milliseconds)) ms, exceeding 350 ms."
            )
        }
        return (markdown.utf8.count, index.matchRanges.count, milliseconds)
    }

    private static func settleWindow(_ window: NSWindow?) async throws {
        guard let window else {
            throw SearchUIVerificationError("The verifier window was not created.")
        }
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 180_000_000)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.superview?.displayIfNeeded()
    }

    private static func format(_ rect: NSRect) -> String {
        String(
            format: "%.0f,%.0f,%.0f,%.0f",
            rect.origin.x,
            rect.origin.y,
            rect.width,
            rect.height
        )
    }

    private static func emit(_ message: String) {
        fputs("\(message)\n", stdout)
        fflush(stdout)
    }

    @MainActor
    private struct DocumentGeometry {
        let workspaceBounds: NSRect
        let scrollFrame: NSRect
        let textFrameSize: NSSize
        let textContainerSize: NSSize

        init(workspace: EditorWorkspaceView) {
            workspaceBounds = workspace.bounds
            scrollFrame = workspace.scrollView.frame
            textFrameSize = workspace.textView.frame.size
            textContainerSize = workspace.textView.textContainer?.containerSize ?? .zero
        }

        func matches(_ other: DocumentGeometry) -> Bool {
            approximatelyEqual(workspaceBounds, other.workspaceBounds)
                && approximatelyEqual(scrollFrame, other.scrollFrame)
                && approximatelyEqual(textFrameSize, other.textFrameSize)
                && approximatelyEqual(textContainerSize, other.textContainerSize)
        }

        var summary: String {
            "workspace=\(format(workspaceBounds)) scroll=\(format(scrollFrame)) text=\(textFrameSize) container=\(textContainerSize)"
        }

        private func approximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
            approximatelyEqual(lhs.origin, rhs.origin) && approximatelyEqual(lhs.size, rhs.size)
        }

        private func approximatelyEqual(_ lhs: NSPoint, _ rhs: NSPoint) -> Bool {
            abs(lhs.x - rhs.x) <= 0.25 && abs(lhs.y - rhs.y) <= 0.25
        }

        private func approximatelyEqual(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
            abs(lhs.width - rhs.width) <= 0.25 && abs(lhs.height - rhs.height) <= 0.25
        }
    }

    private struct Options {
        let fixture: URL
        let evidenceDirectory: URL
        let query: String

        init(arguments: [String]) throws {
            guard let verifierIndex = arguments.firstIndex(of: "--verify-search-ui"),
                arguments.indices.contains(verifierIndex + 1),
                let evidenceIndex = arguments.firstIndex(of: "--evidence-dir"),
                arguments.indices.contains(evidenceIndex + 1)
            else {
                throw SearchUIVerificationError(
                    "Usage: Aviv --verify-search-ui FIXTURE --evidence-dir PATH [--query TEXT]"
                )
            }
            fixture = URL(fileURLWithPath: arguments[verifierIndex + 1])
            evidenceDirectory = URL(fileURLWithPath: arguments[evidenceIndex + 1])
            if let queryIndex = arguments.firstIndex(of: "--query"),
                arguments.indices.contains(queryIndex + 1)
            {
                query = arguments[queryIndex + 1]
            } else {
                query = "search-target"
            }
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                throw SearchUIVerificationError("The search fixture does not exist.")
            }
            guard !query.isEmpty else {
                throw SearchUIVerificationError("The search query must not be empty.")
            }
        }
    }
}

private struct SearchUIVerificationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
