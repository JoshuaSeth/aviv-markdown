import AppKit
import AvivCore
import Foundation

@MainActor
enum AccessibilityVerifier {
    private struct FixtureResult: Codable {
        let name: String
        let loadMilliseconds: Double
        let minimapLineCount: Int
        let sourceRangeCount: Int
        let structureEntryCount: Int
        let accessibilityOutlineItemCount: Int
        let textContainerWidthBefore: Double
        let textContainerWidthAfter: Double
    }

    private struct ElementResult: Codable {
        let identifier: String
        let role: String
        let roleDescription: String
        let label: String
        let help: String
        let value: String
        let enabled: Bool
        let hidden: Bool
    }

    private struct AuditResult: Codable {
        let passed: Bool
        let failures: [String]
        let fixtures: [FixtureResult]
        let elements: [ElementResult]
        let outlineChildIdentifiers: [String]
    }

    private struct Fixture {
        let name: String
        let markdown: String
        let url: URL
        let remotePresentation: RemoteSyncPresentation?
        let minimumOutlineItems: Int
        let maximumLoadSeconds: TimeInterval
    }

    static func runCLI(evidenceDirectory: URL?) -> Int32 {
        let result = verify(evidenceDirectory: evidenceDirectory)
        if result.passed {
            print(
                "accessibility-verifier: PASS (\(result.elements.count) UI elements, \(result.outlineChildIdentifiers.count) outline children, \(result.fixtures.count) document fixtures)"
            )
            return 0
        }

        print("accessibility-verifier: FAIL")
        for failure in result.failures {
            print("- \(failure)")
        }
        return 1
    }

    private static func verify(evidenceDirectory: URL?) -> AuditResult {
        let controller = DocumentWindowController()
        guard let window = controller.window else {
            return AuditResult(
                passed: false,
                failures: ["Document window was not created"],
                fixtures: [],
                elements: [],
                outlineChildIdentifiers: []
            )
        }
        window.setFrame(NSRect(x: 0, y: 0, width: 1_080, height: 820), display: false)
        window.contentView?.layoutSubtreeIfNeeded()

        var failures: [String] = []
        var fixtureResults: [FixtureResult] = []
        for fixture in fixtures {
            let widthBefore = controller.workspace.resolvedTextContainerWidthForTesting
            controller.workspace.setDocumentURL(fixture.url)
            controller.workspace.updateDocumentTitle(url: fixture.url, isEdited: false)
            controller.workspace.updateRemoteSyncPresentation(fixture.remotePresentation)

            let start = CFAbsoluteTimeGetCurrent()
            controller.workspace.loadMarkdown(fixture.markdown)
            settle(controller.workspace)
            let loadSeconds = CFAbsoluteTimeGetCurrent() - start
            let counts = controller.workspace.minimapMetadataCountsForTesting
            let structureEntries = controller.workspace.minimapStructureEntryCountForTesting
            let outlineItems = controller.workspace.outlineAccessibilityItemCountForTesting
            let widthAfter = controller.workspace.resolvedTextContainerWidthForTesting

            fixtureResults.append(
                FixtureResult(
                    name: fixture.name,
                    loadMilliseconds: loadSeconds * 1_000,
                    minimapLineCount: counts.lines,
                    sourceRangeCount: counts.ranges,
                    structureEntryCount: structureEntries,
                    accessibilityOutlineItemCount: outlineItems,
                    textContainerWidthBefore: widthBefore,
                    textContainerWidthAfter: widthAfter
                )
            )

            if counts.lines != counts.ranges {
                failures.append(
                    "\(fixture.name): \(counts.lines) minimap lines != \(counts.ranges) source ranges"
                )
            }
            if structureEntries == 0 {
                failures.append("\(fixture.name): rendered outline structure is empty")
            }
            if outlineItems < fixture.minimumOutlineItems {
                failures.append(
                    "\(fixture.name): \(outlineItems) accessibility outline items < \(fixture.minimumOutlineItems)"
                )
            }
            if loadSeconds > fixture.maximumLoadSeconds {
                failures.append(
                    String(
                        format: "%@: load %.1f ms exceeded %.0f ms",
                        fixture.name,
                        loadSeconds * 1_000,
                        fixture.maximumLoadSeconds * 1_000
                    )
                )
            }
            if abs(widthAfter - widthBefore) > 0.5 {
                failures.append(
                    "\(fixture.name): outline load shifted text-container width from \(widthBefore) to \(widthAfter)"
                )
            }
        }

        controller.workspace.updateRemoteSyncPresentation(
            RemoteSyncPresentation(
                phase: .conflict,
                sourceHost: "pitchai.net",
                isWritable: true,
                detail: "Incoming edits waiting"
            )
        )
        controller.workspace.announceRemoteChange(
            lineRanges: [NSRange(location: 0, length: 18)],
            message: "Incoming edits waiting — local work preserved",
            conflict: true
        )
        settle(controller.workspace)

        let standardViews = accessibilityViews(in: window)
        controller.showDocumentSearchForTesting(query: "Accessibility")
        settle(controller.workspace)
        let searchViews = accessibilityViews(in: window)
        let views = uniqueViews(standardViews + searchViews)
        let conflictAlert = controller.makeRemoteConflictAlert()
        let conflictViews =
            conflictAlert.window.contentView.map {
                [$0] + descendants(of: $0)
            } ?? []
        let results =
            [elementResult(window), elementResult(conflictAlert.window)].compactMap { $0 }
            + (views + conflictViews).compactMap(elementResult)
        let byIdentifier = Dictionary(
            results.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for identifier in requiredElementIdentifiers {
            guard let element = byIdentifier[identifier] else {
                failures.append("Missing accessibility element \(identifier)")
                continue
            }
            if element.role.isEmpty {
                failures.append("\(identifier): missing role")
            }
            if element.roleDescription.isEmpty {
                failures.append("\(identifier): missing role description")
            }
            if element.label.isEmpty {
                failures.append("\(identifier): missing label")
            }
            if element.help.isEmpty {
                failures.append("\(identifier): missing help/description")
            }
            if !element.enabled {
                failures.append("\(identifier): unexpectedly disabled")
            }
            if element.hidden {
                failures.append("\(identifier): unexpectedly hidden")
            }
        }

        for identifier in requiredValueIdentifiers
        where byIdentifier[identifier]?.value.isEmpty != false {
            failures.append("\(identifier): missing accessibility value/state")
        }

        let outlineView = views.first {
            $0.accessibilityIdentifier() == "aviv.document.outline"
        }
        let outlineChildren =
            outlineView?.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        let outlineIdentifiers = outlineChildren.compactMap { $0.accessibilityIdentifier() }
        for kind in [".heading.", ".table.", ".bullet.", ".numbered-list.", ".task."]
        where !outlineIdentifiers.contains(where: { $0.contains(kind) }) {
            failures.append("Document outline is missing an actionable \(kind) accessibility row")
        }
        for child in outlineChildren {
            if child.accessibilityRole() != .row {
                failures.append(
                    "\(child.accessibilityIdentifier() ?? "outline child"): role is not AXRow"
                )
            }
            if (child.accessibilityLabel() ?? "").isEmpty
                || (child.accessibilityHelp() ?? "").isEmpty
                || (child.accessibilityValue() as? String ?? "").isEmpty
            {
                failures.append(
                    "\(child.accessibilityIdentifier() ?? "outline child"): incomplete label/help/value metadata"
                )
            }
        }
        if !outlineChildren.contains(where: {
            ($0.accessibilityValue() as? String)?.contains("contains search matches") == true
                && $0.accessibilityHelp()?.contains("contains search matches") == true
        }) {
            failures.append(
                "Document outline search-hit rows do not expose their highlighted state"
            )
        }
        if let table = outlineChildren.first(where: {
            $0.accessibilityIdentifier()?.contains(".table.") == true
        }) {
            let previousSelection = controller.workspace.textView.selectedRange().location
            if !table.accessibilityPerformPress() {
                failures.append("Table outline row did not perform its navigation action")
            } else if controller.workspace.textView.selectedRange().location == previousSelection {
                failures.append("Table outline row did not move the document editor selection")
            } else if !table.isAccessibilitySelected() {
                failures.append("Table outline row did not expose its selected state")
            }
        } else {
            failures.append("Could not verify table outline navigation action")
        }

        if let evidenceDirectory {
            do {
                try writeEvidenceScreenshot(to: evidenceDirectory)
            } catch {
                failures.append(
                    "Could not write accessibility screenshot: \(error.localizedDescription)"
                )
            }
        }
        var result = AuditResult(
            passed: failures.isEmpty,
            failures: failures,
            fixtures: fixtureResults,
            elements: results.sorted { $0.identifier < $1.identifier },
            outlineChildIdentifiers: outlineIdentifiers
        )
        if let evidenceDirectory {
            do {
                try writeJSON(result, to: evidenceDirectory)
            } catch {
                failures.append(
                    "Could not write accessibility audit: \(error.localizedDescription)"
                )
                result = AuditResult(
                    passed: false,
                    failures: failures,
                    fixtures: fixtureResults,
                    elements: results.sorted { $0.identifier < $1.identifier },
                    outlineChildIdentifiers: outlineIdentifiers
                )
            }
        }
        return result
    }

    private static var fixtures: [Fixture] {
        [
            Fixture(
                name: "normal-local-markdown",
                markdown: "# Local note\n\nA normal local Markdown document.\n\n- One useful item",
                url: URL(fileURLWithPath: "/tmp/Normal Local Note.md"),
                remotePresentation: nil,
                minimumOutlineItems: 2,
                maximumLoadSeconds: 0.75
            ),
            Fixture(
                name: "url-backed-live-trailing-newline",
                markdown: structuredFixture,
                url: URL(string: "https://pitchai.net/aviv-live/seth-live-demo.md")!,
                remotePresentation: RemoteSyncPresentation(
                    phase: .watching,
                    sourceHost: "pitchai.net",
                    isWritable: true,
                    detail: "Live • Save enabled"
                ),
                minimumOutlineItems: 6,
                maximumLoadSeconds: 0.75
            ),
            Fixture(
                name: "large-headings-tables-lists-trailing-newline",
                markdown: largeStructuredFixture,
                url: URL(fileURLWithPath: "/tmp/Large Structured Document.md"),
                remotePresentation: nil,
                minimumOutlineItems: 200,
                maximumLoadSeconds: 2.0
            ),
        ]
    }

    private static var structuredFixture: String {
        """
        # Accessible release plan

        ## Sidebar reliability

        - Bullet insight
        1. Numbered insight
        - [ ] Task insight

        | Surface | State |
        | --- | --- |
        | Outline | Reliable |
        | Accessibility | Rich |
        | Live sync | Inspectable |
        | Conflict controls | Actionable |
        """ + "\n"
    }

    private static var largeStructuredFixture: String {
        (0..<260).map { index in
            """
            ## Section \(index + 1)

            - Outline item \(index + 1)
            1. Numbered outline item \(index + 1)
            - [\(index.isMultiple(of: 2) ? "x" : " ")] Accessibility state \(index + 1)

            | Field | Value |
            | --- | --- |
            | Section | \(index + 1) |

            Large document paragraph \(index + 1) keeps Markdown layout and scrolling realistic.
            """
        }.joined(separator: "\n\n") + "\n"
    }

    private static let requiredElementIdentifiers = [
        "aviv.document.window",
        "aviv.document.workspace",
        "aviv.document.scroll-area",
        "aviv.document.editor",
        "aviv.document.outline",
        "document-title",
        "document-title-visible-text",
        "aviv.document.statistics",
        "aviv.document.format-label",
        "aviv.document.format",
        "aviv.toolbar.new-document",
        "aviv.toolbar.open-document",
        "aviv.toolbar.save-document",
        "aviv.toolbar.zoom-out",
        "aviv.toolbar.actual-size",
        "aviv.toolbar.zoom-in",
        "aviv.toolbar.bold",
        "aviv.toolbar.italic",
        "aviv.toolbar.inline-code",
        "aviv.toolbar.heading-1",
        "aviv.toolbar.heading-2",
        "aviv.toolbar.search",
        "aviv.toolbar.search-field",
        "aviv.toolbar.search-previous",
        "aviv.toolbar.search-next",
        "aviv.toolbar.search-status",
        "aviv.toolbar.search-close",
        "remote-source-badge",
        "remote-source-heartbeat",
        "remote-changed-lines",
        "remote-sync-toast",
        "remote-sync-toast-message",
        "aviv.remote-conflict.dialog",
        "aviv.remote-conflict.use-incoming",
        "aviv.remote-conflict.replace-remote",
        "aviv.remote-conflict.keep-editing",
    ]

    private static let requiredValueIdentifiers = [
        "aviv.document.workspace",
        "aviv.document.editor",
        "aviv.document.outline",
        "document-title",
        "aviv.document.statistics",
        "aviv.document.format",
        "aviv.toolbar.save-document",
        "aviv.toolbar.search-status",
        "remote-source-badge",
        "remote-source-heartbeat",
        "remote-changed-lines",
        "remote-sync-toast",
    ]

    private static func settle(_ workspace: EditorWorkspaceView) {
        workspace.layoutSubtreeIfNeeded()
        if let textContainer = workspace.textView.textContainer {
            workspace.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        workspace.layoutSubtreeIfNeeded()
        workspace.displayIfNeeded()
    }

    private static func accessibilityViews(in window: NSWindow) -> [NSView] {
        var views: [NSView] = []
        if let contentView = window.contentView {
            views.append(contentsOf: [contentView] + descendants(of: contentView))
        }
        if let frameView = window.contentView?.superview {
            views.append(contentsOf: descendants(of: frameView))
        }
        for item in window.toolbar?.items ?? [] {
            if let view = item.view {
                views.append(view)
                views.append(contentsOf: descendants(of: view))
            }
        }
        return uniqueViews(views)
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private static func uniqueViews(_ views: [NSView]) -> [NSView] {
        var seen = Set<ObjectIdentifier>()
        return views.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private static func elementResult(_ view: NSView) -> ElementResult? {
        let identifier = view.accessibilityIdentifier()
        guard !identifier.isEmpty else { return nil }
        return ElementResult(
            identifier: identifier,
            role: view.accessibilityRole().map { String(describing: $0) } ?? "",
            roleDescription: view.accessibilityRoleDescription() ?? "",
            label: view.accessibilityLabel() ?? "",
            help: view.accessibilityHelp() ?? "",
            value: accessibilityValueString(view.accessibilityValue()),
            enabled: view.isAccessibilityEnabled(),
            hidden: view.isAccessibilityHidden()
        )
    }

    private static func elementResult(_ window: NSWindow) -> ElementResult? {
        let identifier = window.accessibilityIdentifier()
        guard !identifier.isEmpty else { return nil }
        return ElementResult(
            identifier: identifier,
            role: window.accessibilityRole().map { String(describing: $0) } ?? "",
            roleDescription: window.accessibilityRoleDescription() ?? "",
            label: window.accessibilityLabel() ?? "",
            help: window.accessibilityHelp() ?? "",
            value: accessibilityValueString(window.accessibilityValue()),
            enabled: window.isAccessibilityEnabled(),
            hidden: window.isAccessibilityHidden()
        )
    }

    private static func accessibilityValueString(_ value: Any?) -> String {
        guard let value else { return "" }
        let string = value as? String ?? String(describing: value)
        let maximumLength = 512
        guard string.count > maximumLength else { return string }
        let end = string.index(string.startIndex, offsetBy: maximumLength - 1)
        return String(string[..<end]) + "…"
    }

    private static func writeJSON(
        _ result: AuditResult,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(
            to: directory.appendingPathComponent("accessibility-audit.json"),
            options: .atomic
        )
    }

    private static func writeEvidenceScreenshot(to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let workspace = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 1_180, height: 920)
        )
        let sourceURL = URL(string: "https://pitchai.net/aviv-live/accessibility-audit.md")!
        workspace.setDocumentURL(sourceURL)
        workspace.updateDocumentTitle(url: sourceURL, isEdited: false)
        workspace.updateRemoteSyncPresentation(
            RemoteSyncPresentation(
                phase: .conflict,
                sourceHost: "pitchai.net",
                isWritable: true,
                detail: "Incoming edits waiting"
            )
        )
        workspace.loadMarkdown(structuredFixture)
        workspace.textView.setSelectedRange(NSRange(location: 0, length: 0))
        workspace.announceRemoteChange(
            lineRanges: [NSRange(location: 0, length: 18)],
            message: "Incoming edits waiting — local work preserved",
            conflict: true
        )
        settle(workspace)
        if let warmBitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) {
            workspace.cacheDisplay(in: workspace.bounds, to: warmBitmap)
            settle(workspace)
        }
        guard let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = workspace.bounds.size
        workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
        guard
            let background = bitmap.colorAt(
                x: min(8, bitmap.pixelsWide - 1),
                y: min(bitmap.pixelsHigh / 2, bitmap.pixelsHigh - 1)
            )?.usingColorSpace(.deviceRGB),
            background.brightnessComponent > 0.7
        else {
            throw AccessibilityVerificationError("Evidence snapshot background was not rendered")
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try png.write(
            to: directory.appendingPathComponent("accessibility-structured-conflict.png"),
            options: .atomic
        )
    }
}

private struct AccessibilityVerificationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
