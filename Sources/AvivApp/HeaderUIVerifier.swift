import AppKit
import AvivCore
import Foundation

@MainActor
enum HeaderUIVerifier {
    private static let widths: [CGFloat] = [720, 840, 1080, 1440]

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
            guard controller.open(url: options.localFile) else {
                throw HeaderUIVerificationError("Aviv could not open the local Markdown fixture.")
            }
            try await settleWindow(controller.window)
            try verifyLocalHeader(controller, expectedURL: options.localFile)
            try resizeAndRender(
                controller,
                width: 1080,
                to: options.evidenceDirectory.appendingPathComponent(
                    "local-native-header-1080.png"
                )
            )
            try renderWorkspaceEvidence(
                controller,
                documentURL: options.localFile,
                width: 1080,
                to: options.evidenceDirectory.appendingPathComponent(
                    "local-workspace-header-1080.png"
                )
            )
            emit("AVIV_HEADER_LOCAL title=\(options.localFile.lastPathComponent) live_status=hidden")

            guard await controller.openRemote(url: options.remoteURL) else {
                throw HeaderUIVerificationError("Aviv could not open the public Markdown URL.")
            }
            try await settleWindow(controller.window)
            for width in widths {
                let geometry = try verifyRemoteHeader(
                    controller,
                    expectedURL: options.remoteURL,
                    width: width
                )
                emit(
                    "AVIV_HEADER_REMOTE width=\(Int(width)) title_centered=true native_title=hidden indicator=\(format(geometry.indicatorFrame)) traffic_lights=\(format(geometry.trafficLightFrame))"
                )
            }
            for width in [CGFloat(720), 1080] {
                try resizeAndRender(
                    controller,
                    width: width,
                    to: options.evidenceDirectory.appendingPathComponent(
                        "remote-native-header-\(Int(width)).png"
                    )
                )
                try renderWorkspaceEvidence(
                    controller,
                    documentURL: options.remoteURL,
                    width: width,
                    to: options.evidenceDirectory.appendingPathComponent(
                        "remote-workspace-header-\(Int(width)).png"
                    )
                )
            }
            controller.stopRemoteSync()
            controller.close()
            emit("header-ui-verifier: PASS")
            return 0
        } catch {
            fputs("header-ui-verifier: FAIL: \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            return 1
        }
    }

    private static func verifyLocalHeader(
        _ controller: DocumentWindowController,
        expectedURL: URL
    ) throws {
        guard let window = controller.window else {
            throw HeaderUIVerificationError("The local document has no window.")
        }
        try verifySingleCenteredTitle(
            controller,
            expectedTitle: expectedURL.lastPathComponent
        )
        guard window.titleVisibility == .hidden else {
            throw HeaderUIVerificationError("AppKit is still painting a duplicate window title.")
        }
        guard controller.liveDocumentIndicatorFrameForTesting == nil else {
            throw HeaderUIVerificationError("The local document incorrectly shows a live status.")
        }
    }

    private static func verifyRemoteHeader(
        _ controller: DocumentWindowController,
        expectedURL: URL,
        width: CGFloat
    ) throws -> HeaderGeometry {
        guard let window = controller.window else {
            throw HeaderUIVerificationError("The live document has no window.")
        }
        window.setContentSize(NSSize(width: width, height: 720))
        layoutWindow(window)

        try verifySingleCenteredTitle(
            controller,
            expectedTitle: expectedURL.lastPathComponent
        )
        guard window.titleVisibility == .hidden else {
            throw HeaderUIVerificationError("AppKit is still painting a duplicate live title.")
        }
        guard let indicatorFrame = controller.liveDocumentIndicatorFrameForTesting else {
            throw HeaderUIVerificationError("The live document status is hidden.")
        }
        guard controller.liveDocumentIndicatorVisibleTextForTesting.isEmpty else {
            throw HeaderUIVerificationError("The live status still paints duplicate side text.")
        }
        guard
            controller.liveDocumentIndicatorAccessibilitySummaryForTesting.contains(
                expectedURL.host ?? ""
            )
        else {
            throw HeaderUIVerificationError("The compact live status lost its source description.")
        }

        let titleFrame = controller.documentTitleFrameForTesting
        let trafficLightFrame = try trafficLightFrame(in: controller.workspace, window: window)
        let toolbarButtonFrames = try toolbarButtonFrames(
            in: controller.workspace,
            window: window
        )
        guard abs(titleFrame.midX - controller.workspace.bounds.midX) <= 0.5 else {
            throw HeaderUIVerificationError("The document title is not centered at width \(Int(width)).")
        }
        guard !indicatorFrame.intersects(titleFrame) else {
            throw HeaderUIVerificationError("The live status overlaps the title at width \(Int(width)).")
        }
        guard !indicatorFrame.intersects(trafficLightFrame.insetBy(dx: -8, dy: -8)) else {
            throw HeaderUIVerificationError(
                "The live status overlaps the macOS traffic lights at width \(Int(width))."
            )
        }
        let titleCollisions = toolbarButtonFrames.filter {
            $0.intersects(titleFrame.insetBy(dx: -6, dy: -2))
        }
        guard titleCollisions.isEmpty else {
            throw HeaderUIVerificationError(
                "A native toolbar action overlaps the centered title at width \(Int(width)): title=\(format(titleFrame)) controls=\(format(titleCollisions))."
            )
        }
        let indicatorCollisions = toolbarButtonFrames.filter {
            $0.intersects(indicatorFrame.insetBy(dx: -2, dy: -2))
        }
        guard indicatorCollisions.isEmpty else {
            throw HeaderUIVerificationError(
                "A native toolbar action overlaps the live status at width \(Int(width)): indicator=\(format(indicatorFrame)) controls=\(format(indicatorCollisions))."
            )
        }
        return HeaderGeometry(
            indicatorFrame: indicatorFrame,
            trafficLightFrame: trafficLightFrame
        )
    }

    private static func verifySingleCenteredTitle(
        _ controller: DocumentWindowController,
        expectedTitle: String
    ) throws {
        guard let window = controller.window else {
            throw HeaderUIVerificationError("The document has no window.")
        }
        layoutWindow(window)
        guard window.title == expectedTitle else {
            throw HeaderUIVerificationError("AppKit document metadata has the wrong title.")
        }
        guard controller.documentTitleTextForTesting == expectedTitle else {
            throw HeaderUIVerificationError("The centered document title has the wrong text.")
        }
        let frame = controller.documentTitleFrameForTesting
        guard abs(frame.midX - controller.workspace.bounds.midX) <= 0.5 else {
            throw HeaderUIVerificationError("The visible document title is not centered.")
        }
        let toolbarFrames = try toolbarButtonFrames(
            in: controller.workspace,
            window: window
        )
        let collisions = toolbarFrames.filter {
            $0.intersects(frame.insetBy(dx: -6, dy: -2))
        }
        guard collisions.isEmpty else {
            throw HeaderUIVerificationError(
                "A native toolbar action overlaps the visible document title: title=\(format(frame)) controls=\(format(collisions))."
            )
        }
    }

    private static func trafficLightFrame(
        in workspace: EditorWorkspaceView,
        window: NSWindow
    ) throws -> NSRect {
        let buttons = [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ].compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3 else {
            throw HeaderUIVerificationError("The native traffic-light controls are unavailable.")
        }
        return buttons
            .map { workspace.convert($0.bounds, from: $0) }
            .reduce(NSRect.null) { $0.union($1) }
    }

    private static func toolbarButtonFrames(
        in workspace: EditorWorkspaceView,
        window: NSWindow
    ) throws -> [NSRect] {
        guard let frameView = window.contentView?.superview else {
            throw HeaderUIVerificationError("The native toolbar hierarchy is unavailable.")
        }
        let toolbarBand = NSRect(
            x: workspace.bounds.minX,
            y: workspace.bounds.maxY - 54,
            width: workspace.bounds.width,
            height: 54
        )
        var frames: [NSRect] = []
        func collectButtons(from view: NSView) {
            if view is NSButton, !view.isHidden, view.alphaValue > 0 {
                let frame = workspace.convert(view.bounds, from: view)
                if frame.intersects(toolbarBand) {
                    frames.append(frame)
                }
            }
            view.subviews.forEach { collectButtons(from: $0) }
        }
        collectButtons(from: frameView)
        return frames
    }

    private static func resizeAndRender(
        _ controller: DocumentWindowController,
        width: CGFloat,
        to url: URL
    ) throws {
        guard let window = controller.window,
            let contentView = window.contentView,
            let frameView = contentView.superview
        else {
            throw HeaderUIVerificationError("The native window frame is unavailable for capture.")
        }
        window.setContentSize(NSSize(width: width, height: 720))
        layoutWindow(window)
        frameView.displayIfNeeded()
        let captureBounds = NSRect(
            x: frameView.bounds.minX,
            y: frameView.bounds.maxY - min(48, frameView.bounds.height),
            width: frameView.bounds.width,
            height: min(48, frameView.bounds.height)
        )
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: captureBounds) else {
            throw HeaderUIVerificationError("Could not allocate a native-window evidence bitmap.")
        }
        bitmap.size = captureBounds.size
        frameView.cacheDisplay(in: captureBounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw HeaderUIVerificationError("Could not encode the native-window evidence PNG.")
        }
        try png.write(to: url, options: .atomic)
    }

    private static func renderWorkspaceEvidence(
        _ controller: DocumentWindowController,
        documentURL: URL,
        width: CGFloat,
        to url: URL
    ) throws {
        let snapshot = EditorWorkspaceView(
            frame: NSRect(x: 0, y: 0, width: width, height: 720)
        )
        snapshot.documentFormat = controller.workspace.documentFormat
        snapshot.loadMarkdown(controller.workspace.textView.string)
        snapshot.updateDocumentTitle(url: documentURL, isEdited: false)
        snapshot.layoutSubtreeIfNeeded()
        snapshot.displayIfNeeded()
        guard let bitmap = snapshot.bitmapImageRepForCachingDisplay(in: snapshot.bounds) else {
            throw HeaderUIVerificationError("Could not allocate a workspace evidence bitmap.")
        }
        bitmap.size = snapshot.bounds.size
        snapshot.cacheDisplay(in: snapshot.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw HeaderUIVerificationError("Could not encode the workspace evidence PNG.")
        }
        try png.write(to: url, options: .atomic)
    }

    private static func settleWindow(_ window: NSWindow?) async throws {
        guard let window else {
            throw HeaderUIVerificationError("The verifier window was not created.")
        }
        layoutWindow(window)
        try await Task.sleep(nanoseconds: 200_000_000)
        layoutWindow(window)
        window.contentView?.superview?.displayIfNeeded()
    }

    private static func layoutWindow(_ window: NSWindow) {
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
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

    private static func format(_ rects: [NSRect]) -> String {
        rects.map { format($0) }.joined(separator: ";")
    }

    private static func emit(_ message: String) {
        fputs("\(message)\n", stdout)
        fflush(stdout)
    }

    private struct HeaderGeometry {
        let indicatorFrame: NSRect
        let trafficLightFrame: NSRect
    }

    private struct Options {
        let remoteURL: URL
        let localFile: URL
        let evidenceDirectory: URL

        init(arguments: [String]) throws {
            guard let verifierIndex = arguments.firstIndex(of: "--verify-header-ui"),
                arguments.indices.contains(verifierIndex + 1),
                let remoteURL = URL(string: arguments[verifierIndex + 1]),
                RemoteMarkdownSource.isAllowedRemoteURL(remoteURL),
                let localIndex = arguments.firstIndex(of: "--local-file"),
                arguments.indices.contains(localIndex + 1),
                let evidenceIndex = arguments.firstIndex(of: "--evidence-dir"),
                arguments.indices.contains(evidenceIndex + 1)
            else {
                throw HeaderUIVerificationError(
                    "Usage: Aviv --verify-header-ui HTTPS_URL --local-file PATH --evidence-dir PATH"
                )
            }
            let localFile = URL(fileURLWithPath: arguments[localIndex + 1])
            guard localFile.isFileURL,
                FileManager.default.fileExists(atPath: localFile.path)
            else {
                throw HeaderUIVerificationError("The local Markdown fixture does not exist.")
            }
            self.remoteURL = remoteURL
            self.localFile = localFile
            self.evidenceDirectory = URL(fileURLWithPath: arguments[evidenceIndex + 1])
        }
    }
}

private struct HeaderUIVerificationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
