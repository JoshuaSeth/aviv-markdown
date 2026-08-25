import AppKit
import XCTest

@testable import AvivCore

final class StyledMarkerRevealTests: XCTestCase {
    @MainActor
    func testEveryHeadingLevelPaintsItsRawMarkerAndClickAwayRestoresReadingMode() throws {
        for level in 1...6 {
            let marker = String(repeating: "#", count: level)
            let body = "Heading level \(level)"
            let markdown = "\(marker) \(body)\n\nPlain click-away destination."
            let workspace = makeWorkspace(markdown: markdown)
            let nsString = markdown as NSString
            let bodyRange = nsString.range(of: body)
            let clickAway = nsString.range(of: "Plain click-away destination")

            workspace.textView.setSelectedRange(
                NSRange(location: clickAway.location, length: 0)
            )
            settle(workspace)
            _ = try snapshot(workspace)
            let reading = try snapshot(workspace)
            let readingBodyFrame = try frame(for: bodyRange, workspace: workspace)

            workspace.textView.setSelectedRange(
                NSRange(location: bodyRange.location, length: 0)
            )
            settle(workspace)
            let focusedMarkers = workspace.styledMarkerFramesForTesting
            let focused = try snapshot(workspace)
            let focusedBodyFrame = try frame(for: bodyRange, workspace: workspace)

            XCTAssertEqual(focusedMarkers.map(\.token.label), [marker], "heading level \(level)")
            XCTAssertTrue(
                focusedMarkers.allSatisfy { $0.token.role == .heading },
                "heading level \(level) used the wrong marker role"
            )
            let markerRegion = union(of: focusedMarkers.map(\.frame)).insetBy(dx: -3, dy: -3)
            XCTAssertGreaterThan(
                maximumPixelDifference(
                    between: reading,
                    and: focused,
                    in: markerRegion,
                    viewBounds: workspace.bounds
                ),
                0,
                "focusing heading level \(level) did not paint \(marker)"
            )
            XCTAssertLessThanOrEqual(
                rectDelta(readingBodyFrame, focusedBodyFrame),
                0.01,
                "heading level \(level) shifted while revealing its marker"
            )

            workspace.textView.setSelectedRange(
                NSRange(location: clickAway.location, length: 0)
            )
            settle(workspace)
            let restored = try snapshot(workspace)
            let restoredBodyFrame = try frame(for: bodyRange, workspace: workspace)

            XCTAssertEqual(
                maximumPixelDifference(
                    between: reading,
                    and: restored,
                    in: markerRegion,
                    viewBounds: workspace.bounds
                ),
                0,
                "clicking away did not restore heading level \(level)"
            )
            XCTAssertLessThanOrEqual(rectDelta(readingBodyFrame, restoredBodyFrame), 0.01)
            XCTAssertEqual(workspace.textView.string, markdown)
        }
    }

    @MainActor
    func testEveryHiddenInlineBlockAndCustomMarkerPaintsAndRestores() throws {
        let cases = [
            RevealCase(
                name: "strong",
                markdown: "Intro\n\nBefore **strong marker** after.\n\nPlain click-away destination.",
                focusNeedle: "strong marker",
                expectedLabels: ["**", "**"]
            ),
            RevealCase(
                name: "emphasis",
                markdown: "Intro\n\nBefore _emphasis marker_ after.\n\nPlain click-away destination.",
                focusNeedle: "emphasis marker",
                expectedLabels: ["_", "_"]
            ),
            RevealCase(
                name: "strikethrough",
                markdown: "Intro\n\nBefore ~~strike marker~~ after.\n\nPlain click-away destination.",
                focusNeedle: "strike marker",
                expectedLabels: ["~~", "~~"]
            ),
            RevealCase(
                name: "inline code",
                markdown: "Intro\n\nBefore `code marker` after.\n\nPlain click-away destination.",
                focusNeedle: "code marker",
                expectedLabels: ["`", "`"]
            ),
            RevealCase(
                name: "link",
                markdown:
                    "Intro\n\nBefore [link marker](https://example.com/path) after.\n\nPlain click-away destination.",
                focusNeedle: "link marker",
                expectedLabels: ["[link marker](https://example.com/path)"]
            ),
            RevealCase(
                name: "rendered image",
                markdown:
                    "Intro\n\n![diagram marker](missing-diagram.png)\n\nPlain click-away destination.",
                focusNeedle: "diagram marker",
                expectedLabels: ["![diagram marker](missing-diagram.png)"]
            ),
            RevealCase(
                name: "fenced code",
                markdown:
                    "Intro\n\n```swift\nlet markerValue = 1\n```\n\nPlain click-away destination.",
                focusNeedle: "swift",
                expectedLabels: ["```swift"]
            ),
        ]

        for revealCase in cases {
            let workspace = makeWorkspace(markdown: revealCase.markdown)
            let nsString = revealCase.markdown as NSString
            let focusRange = nsString.range(of: revealCase.focusNeedle)
            let clickAway = nsString.range(of: "Plain click-away destination")
            XCTAssertNotEqual(focusRange.location, NSNotFound, revealCase.name)
            XCTAssertNotEqual(clickAway.location, NSNotFound, revealCase.name)

            workspace.textView.setSelectedRange(
                NSRange(location: clickAway.location, length: 0)
            )
            settle(workspace)
            _ = try snapshot(workspace)
            let reading = try snapshot(workspace)
            let readingFocusFrame = try frame(for: focusRange, workspace: workspace)

            workspace.textView.setSelectedRange(
                NSRange(location: focusRange.location, length: 0)
            )
            settle(workspace)
            let focusedMarkers = workspace.styledMarkerFramesForTesting
            let focused = try snapshot(workspace)
            let focusedFocusFrame = try frame(for: focusRange, workspace: workspace)

            XCTAssertEqual(
                focusedMarkers.map(\.token.label),
                revealCase.expectedLabels,
                revealCase.name
            )
            XCTAssertFalse(focusedMarkers.isEmpty, revealCase.name)
            let markerRegion = union(of: focusedMarkers.map(\.frame)).insetBy(dx: -3, dy: -3)
            XCTAssertGreaterThan(
                maximumPixelDifference(
                    between: reading,
                    and: focused,
                    in: markerRegion,
                    viewBounds: workspace.bounds
                ),
                0,
                "\(revealCase.name) did not paint its raw marker"
            )
            XCTAssertLessThanOrEqual(
                rectDelta(readingFocusFrame, focusedFocusFrame),
                0.01,
                "\(revealCase.name) shifted while revealing its marker"
            )

            workspace.textView.setSelectedRange(
                NSRange(location: clickAway.location, length: 0)
            )
            settle(workspace)
            let restored = try snapshot(workspace)
            let restoredFocusFrame = try frame(for: focusRange, workspace: workspace)

            XCTAssertEqual(
                maximumPixelDifference(
                    between: reading,
                    and: restored,
                    in: markerRegion,
                    viewBounds: workspace.bounds
                ),
                0,
                "\(revealCase.name) did not restore its reading presentation"
            )
            XCTAssertLessThanOrEqual(rectDelta(readingFocusFrame, restoredFocusFrame), 0.01)
            XCTAssertEqual(workspace.textView.string, revealCase.markdown, revealCase.name)
        }
    }

    @MainActor
    func testTableRowRevealsRawSourceAndRestoresRenderedTable() throws {
        let markdown = """
            Intro

            | Name | Value |
            | ---- | ----- |
            | Alpha marker | Beta |

            Plain click-away destination.
            """
        let workspace = makeWorkspace(markdown: markdown)
        let nsString = markdown as NSString
        let tableCell = nsString.range(of: "Alpha marker")
        let tablePipe = nsString.range(of: "| Alpha marker").location
        let clickAway = nsString.range(of: "Plain click-away destination")

        workspace.textView.setSelectedRange(NSRange(location: clickAway.location, length: 0))
        settle(workspace)
        _ = try snapshot(workspace)
        let reading = try snapshot(workspace)
        let readingFrame = try lineFrame(containing: tableCell, workspace: workspace)
        XCTAssertEqual(alpha(at: tablePipe, workspace: workspace), 0, accuracy: 0.001)

        workspace.textView.setSelectedRange(NSRange(location: tableCell.location, length: 0))
        settle(workspace)
        let focused = try snapshot(workspace)
        let focusedFrame = try lineFrame(containing: tableCell, workspace: workspace)
        XCTAssertGreaterThan(alpha(at: tablePipe, workspace: workspace), 0.9)
        XCTAssertGreaterThan(
            maximumPixelDifference(
                between: reading,
                and: focused,
                in: readingFrame.insetBy(dx: -4, dy: -4),
                viewBounds: workspace.bounds
            ),
            0,
            "focusing a rendered table row did not reveal raw pipes and source"
        )
        XCTAssertLessThanOrEqual(rectDelta(readingFrame, focusedFrame), 0.01)

        workspace.textView.setSelectedRange(NSRange(location: clickAway.location, length: 0))
        settle(workspace)
        let restored = try snapshot(workspace)
        let restoredFrame = try lineFrame(containing: tableCell, workspace: workspace)
        XCTAssertEqual(alpha(at: tablePipe, workspace: workspace), 0, accuracy: 0.001)
        XCTAssertEqual(
            maximumPixelDifference(
                between: reading,
                and: restored,
                in: readingFrame.insetBy(dx: -4, dy: -4),
                viewBounds: workspace.bounds
            ),
            0,
            "clicking away did not restore the rendered table"
        )
        XCTAssertLessThanOrEqual(rectDelta(readingFrame, restoredFrame), 0.01)
        XCTAssertEqual(workspace.textView.string, markdown)
    }

    @MainActor
    func testListsTasksBlockquotesAndRulesKeepTheirEditableStructuralMarkers() throws {
        let markdown = """
            - Unordered marker
            2. Ordered marker
            - [x] Task marker
            > Quote marker
            ---

            Plain click-away destination.
            """
        let workspace = makeWorkspace(markdown: markdown)
        let nsString = markdown as NSString
        let markers = [
            nsString.range(of: "-").location,
            nsString.range(of: "2.").location,
            nsString.range(of: "[x]").location,
            nsString.range(of: ">").location,
            nsString.range(of: "---", options: .backwards).location,
        ]
        let bodies = ["Unordered marker", "Ordered marker", "Task marker", "Quote marker"]
        let clickAway = nsString.range(of: "Plain click-away destination")
        let taskBody = nsString.range(of: "Task marker")

        workspace.textView.setSelectedRange(NSRange(location: clickAway.location, length: 0))
        settle(workspace)
        _ = try snapshot(workspace)
        let reading = try snapshot(workspace)
        let readingAlphas = markers.map { alpha(at: $0, workspace: workspace) }
        XCTAssertGreaterThan(readingAlphas[0], 0.9)
        XCTAssertGreaterThan(readingAlphas[1], 0.9)
        XCTAssertGreaterThan(readingAlphas[2], 0.9)
        XCTAssertGreaterThan(readingAlphas[3], 0.9)
        XCTAssertGreaterThan(readingAlphas[4], 0.9)
        XCTAssertTrue(
            workspace.styledMarkerFramesForTesting.allSatisfy { $0.token.role != .listMarker }
        )

        for body in bodies {
            let bodyRange = nsString.range(of: body)
            workspace.textView.setSelectedRange(NSRange(location: bodyRange.location, length: 0))
            settle(workspace)
            XCTAssertEqual(
                markers.map { alpha(at: $0, workspace: workspace) },
                readingAlphas,
                "\(body) changed a structural source glyph instead of keeping it editable"
            )
            XCTAssertEqual(workspace.textView.string, markdown)
        }

        workspace.textView.setSelectedRange(NSRange(location: taskBody.location, length: 0))
        settle(workspace)
        let taskMarkers = workspace.styledMarkerFramesForTesting.filter {
            $0.token.role == .listMarker
        }
        XCTAssertEqual(taskMarkers.map(\.token.label), ["-"])
        let focused = try snapshot(workspace)
        let markerRegion = union(of: taskMarkers.map(\.frame)).insetBy(dx: -3, dy: -3)
        XCTAssertGreaterThan(
            maximumPixelDifference(
                between: reading,
                and: focused,
                in: markerRegion,
                viewBounds: workspace.bounds
            ),
            0,
            "focusing a task did not reveal its hidden list marker"
        )

        workspace.textView.setSelectedRange(NSRange(location: clickAway.location, length: 0))
        settle(workspace)
        let restored = try snapshot(workspace)
        XCTAssertTrue(
            workspace.styledMarkerFramesForTesting.allSatisfy { $0.token.role != .listMarker }
        )
        XCTAssertEqual(
            maximumPixelDifference(
                between: reading,
                and: restored,
                in: markerRegion,
                viewBounds: workspace.bounds
            ),
            0,
            "clicking away did not restore the task-list presentation"
        )
        XCTAssertEqual(workspace.textView.string, markdown)
    }

    private struct RevealCase {
        let name: String
        let markdown: String
        let focusNeedle: String
        let expectedLabels: [String]
    }

    private struct Snapshot {
        let data: Data
        let pixelsWide: Int
        let pixelsHigh: Int
        let bytesPerRow: Int
        let bytesPerPixel: Int
    }

    @MainActor
    private func makeWorkspace(markdown: String) -> EditorWorkspaceView {
        let workspace = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: 1040, height: 740)
        )
        workspace.loadMarkdown(markdown)
        workspace.updateDocumentTitle(
            url: URL(fileURLWithPath: "Styled Marker Reveal.md"),
            isEdited: false
        )
        settle(workspace)
        return workspace
    }

    @MainActor
    private func settle(_ workspace: EditorWorkspaceView) {
        workspace.layoutSubtreeIfNeeded()
        workspace.needsDisplay = true
        workspace.textView.needsDisplay = true
        workspace.displayIfNeeded()
    }

    @MainActor
    private func snapshot(_ workspace: EditorWorkspaceView) throws -> Snapshot {
        guard let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) else {
            throw SnapshotError.allocationFailed
        }
        bitmap.size = workspace.bounds.size
        workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
        guard let pointer = bitmap.bitmapData else {
            throw SnapshotError.missingBitmapData
        }
        return Snapshot(
            data: Data(bytes: pointer, count: bitmap.bytesPerRow * bitmap.pixelsHigh),
            pixelsWide: bitmap.pixelsWide,
            pixelsHigh: bitmap.pixelsHigh,
            bytesPerRow: bitmap.bytesPerRow,
            bytesPerPixel: max(1, bitmap.bitsPerPixel / 8)
        )
    }

    @MainActor
    private func frame(
        for characterRange: NSRange,
        workspace: EditorWorkspaceView
    ) throws -> NSRect {
        guard let layoutManager = workspace.textView.layoutManager,
            let textContainer = workspace.textView.textContainer
        else {
            throw SnapshotError.missingTextLayout
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
        rect.origin.x += workspace.textView.textContainerOrigin.x
        rect.origin.y += workspace.textView.textContainerOrigin.y
        return workspace.textView.convert(rect, to: workspace)
    }

    @MainActor
    private func lineFrame(
        containing range: NSRange,
        workspace: EditorWorkspaceView
    ) throws -> NSRect {
        let lineRange = (workspace.textView.string as NSString).lineRange(for: range)
        return try frame(for: lineRange, workspace: workspace)
    }

    @MainActor
    private func alpha(at location: Int, workspace: EditorWorkspaceView) -> CGFloat {
        guard let color = workspace.textView.textStorage?.attribute(
            .foregroundColor,
            at: location,
            effectiveRange: nil
        ) as? NSColor else {
            return 0
        }
        return color.usingColorSpace(.deviceRGB)?.alphaComponent ?? color.alphaComponent
    }

    private func union(of rects: [NSRect]) -> NSRect {
        precondition(!rects.isEmpty)
        return rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    }

    private func rectDelta(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        max(
            abs(lhs.minX - rhs.minX),
            abs(lhs.minY - rhs.minY),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height)
        )
    }

    private func maximumPixelDifference(
        between lhs: Snapshot,
        and rhs: Snapshot,
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
                between: lhs,
                and: rhs,
                minimumX: minimumX,
                maximumX: maximumX,
                minimumY: directMinimumY,
                maximumY: directMaximumY
            ),
            pixelDifference(
                between: lhs,
                and: rhs,
                minimumX: minimumX,
                maximumX: maximumX,
                minimumY: mirroredMinimumY,
                maximumY: mirroredMaximumY
            )
        )
    }

    private func pixelDifference(
        between lhs: Snapshot,
        and rhs: Snapshot,
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

    private enum SnapshotError: Error {
        case allocationFailed
        case missingBitmapData
        case missingTextLayout
    }
}
