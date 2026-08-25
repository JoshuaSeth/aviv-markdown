import AppKit
import AvivCore
import Darwin
import Foundation

@MainActor
enum RemoteMarkdownLiveVerifier {
    private static let cleanMarker = "Live agent update: external change received."
    private static let conflictMarker =
        "External agent update waiting for conflict resolution."
    private static let localMarker = "<!-- local-unsaved-verifier -->"

    static func runCLI(arguments: [String]) async -> Int32 {
        do {
            let options = try Options(arguments: arguments)
            let token = try String(contentsOf: options.tokenFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                throw VerificationError("The verifier token file is empty.")
            }

            let controller = DocumentWindowController(
                remoteCredentialStore: FixedRemoteWriteCredentialStore(token: token)
            )
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            guard await controller.openRemote(url: options.url) else {
                throw VerificationError("Aviv could not open the public Markdown URL.")
            }
            guard let source = controller.representedRemoteSource,
                source.isWritable,
                source.pollingInterval == 1,
                source.validator.etag != nil
            else {
                throw VerificationError("The URL did not expose the complete live-source contract.")
            }

            let anchor = "11. Stable anchor for the live viewport check."
            let anchorRange = (controller.workspace.textView.string as NSString).range(of: anchor)
            guard anchorRange.location != NSNotFound else {
                throw VerificationError("The public fixture is missing its viewport anchor.")
            }
            controller.workspace.textView.setSelectedRange(
                NSRange(location: anchorRange.location, length: 0)
            )
            controller.workspace.textView.scrollRangeToVisible(anchorRange)
            controller.workspace.layoutSubtreeIfNeeded()

            let indicatorCount = Set(controller.remoteIndicatorIdentifiersForTesting)
                .count
            guard indicatorCount >= 5 else {
                throw VerificationError("Fewer than five external-edit indicators are installed.")
            }
            let cleanStarted = Date()
            emit(
                "AVIV_REMOTE_READY_CLEAN source=\(source.sourceID) poll=\(source.pollingInterval)s indicators=\(indicatorCount)"
            )
            try await wait(until: {
                controller.workspace.textView.string.contains(cleanMarker)
            })
            let cleanElapsed = Date().timeIntervalSince(cleanStarted)
            guard let update = controller.lastExternalUpdateResult else {
                throw VerificationError("The external edit did not use the in-place update path.")
            }
            let mappedCaret = controller.workspace.textView.selectedRange().location
            let mappedTail = (controller.workspace.textView.string as NSString).substring(
                from: mappedCaret
            )
            guard mappedTail.hasPrefix(anchor), abs(update.visibleAnchorDelta) <= 1,
                abs(update.textContainerWidthDelta) <= 0.1
            else {
                throw VerificationError(
                    "The clean external edit moved the caret, viewport, or layout."
                )
            }
            try renderEvidence(
                from: controller.workspace,
                sourceURL: options.url,
                presentation: RemoteSyncPresentation(
                    phase: .incomingApplied,
                    sourceHost: source.displayHost,
                    isWritable: true,
                    detail: "External edit applied"
                ),
                message: "External edits applied",
                conflict: false,
                marker: cleanMarker,
                to: options.evidenceDirectory.appendingPathComponent("remote-clean-update.png")
            )
            emit(
                String(
                    format:
                        "AVIV_REMOTE_CLEAN_APPLIED elapsed=%.3fs viewport_delta=%.3f width_delta=%.3f",
                    cleanElapsed,
                    update.visibleAnchorDelta,
                    update.textContainerWidthDelta
                )
            )

            controller.workspace.textView.loadMarkdown(
                controller.workspace.textView.string + "\n\(localMarker)\n"
            )
            controller.isEdited = true
            emit("AVIV_REMOTE_READY_CONFLICT local_preserved=true")
            try await wait(until: { controller.hasPendingRemoteConflict })
            let visibleMarkdown = controller.workspace.textView.string
            let pending = await controller.remoteSyncController?.pendingIncomingSnapshot()
            guard visibleMarkdown.contains(localMarker), !visibleMarkdown.contains(conflictMarker),
                pending?.markdown.contains(conflictMarker) == true
            else {
                throw VerificationError("The conflict path did not preserve the local buffer.")
            }
            try renderEvidence(
                from: controller.workspace,
                sourceURL: options.url,
                presentation: RemoteSyncPresentation(
                    phase: .conflict,
                    sourceHost: source.displayHost,
                    isWritable: true,
                    detail: "Incoming edit waiting"
                ),
                message: "Incoming edits waiting — local work preserved",
                conflict: true,
                marker: "## Shared working notes",
                to: options.evidenceDirectory.appendingPathComponent(
                    "remote-conflict-preserved.png"
                )
            )
            emit("AVIV_REMOTE_CONFLICT_PRESERVED incoming_waiting=true overwrite=false")

            guard await controller.openRemote(url: options.url) else {
                throw VerificationError("Aviv could not reopen the latest remote version.")
            }
            guard let preSaveETag = controller.representedRemoteSource?.validator.etag else {
                throw VerificationError("The reopened source has no save validator.")
            }
            let saveMarker = "<!-- command-s-verifier-\(Int(Date().timeIntervalSince1970)) -->"
            controller.workspace.textView.loadMarkdown(
                controller.workspace.textView.string + "\n\(saveMarker)\n"
            )
            controller.isEdited = true
            controller.saveDocument(nil)
            try await wait(until: {
                controller.isEdited == false
                    && controller.representedRemoteSource?.validator.etag != preSaveETag
            })
            guard controller.representedRemoteSource?.resolvedURL == options.url else {
                throw VerificationError("Saving changed the public polling URL.")
            }
            let readback = try await URLSessionRemoteMarkdownTransport().fetch(
                from: options.url,
                openedURL: options.url,
                validator: nil
            )
            guard case .document(let savedSnapshot) = readback,
                savedSnapshot.markdown.contains(saveMarker)
            else {
                throw VerificationError(
                    "Command-S did not persist through the public backing source."
                )
            }
            try renderEvidence(
                from: controller.workspace,
                sourceURL: options.url,
                presentation: RemoteSyncPresentation(
                    phase: .saved,
                    sourceHost: source.displayHost,
                    isWritable: true,
                    detail: "Saved to source"
                ),
                message: "Saved securely to source",
                conflict: false,
                marker: "## Shared working notes",
                to: options.evidenceDirectory.appendingPathComponent("remote-command-s-saved.png")
            )
            emit(
                "AVIV_REMOTE_COMMAND_S_SAVED etag_changed=true public_readback=true source=\(source.sourceID)"
            )
            controller.close()
            emit("remote-live-verifier: PASS")
            return 0
        } catch {
            fputs("remote-live-verifier: FAIL: \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            return 1
        }
    }

    private static func wait(
        timeout: TimeInterval = 20,
        until condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VerificationError("Timed out waiting for the coordinated live-source change.")
    }

    private static func renderEvidence(
        from liveWorkspace: EditorWorkspaceView,
        sourceURL: URL,
        presentation: RemoteSyncPresentation,
        message: String,
        conflict: Bool,
        marker: String,
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let snapshot = EditorWorkspaceView(frame: liveWorkspace.bounds)
        snapshot.documentFormat = liveWorkspace.documentFormat
        snapshot.loadMarkdown(liveWorkspace.textView.string)
        snapshot.updateDocumentTitle(url: sourceURL, isEdited: conflict)
        snapshot.updateRemoteSyncPresentation(presentation)
        let markerRange = (snapshot.textView.string as NSString).range(of: marker)
        let lineRanges: [NSRange]
        if markerRange.location == NSNotFound {
            lineRanges = []
        } else {
            lineRanges = [
                (snapshot.textView.string as NSString).lineRange(for: markerRange)
            ]
            snapshot.textView.setSelectedRange(
                NSRange(location: markerRange.location, length: 0)
            )
            snapshot.textView.scrollRangeToVisible(markerRange)
        }
        snapshot.announceRemoteChange(
            lineRanges: lineRanges,
            message: message,
            conflict: conflict
        )
        snapshot.layoutSubtreeIfNeeded()
        snapshot.displayIfNeeded()
        guard let bitmap = snapshot.bitmapImageRepForCachingDisplay(in: snapshot.bounds) else {
            throw VerificationError("Could not allocate a live-sync evidence bitmap.")
        }
        bitmap.size = snapshot.bounds.size
        snapshot.cacheDisplay(in: snapshot.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw VerificationError("Could not encode the live-sync evidence PNG.")
        }
        try png.write(to: url, options: .atomic)
    }

    private static func emit(_ message: String) {
        fputs("\(message)\n", stdout)
        fflush(stdout)
    }

    private struct Options {
        let url: URL
        let tokenFile: URL
        let evidenceDirectory: URL

        init(arguments: [String]) throws {
            guard let verifierIndex = arguments.firstIndex(of: "--verify-remote-live"),
                arguments.indices.contains(verifierIndex + 1),
                let url = URL(string: arguments[verifierIndex + 1]),
                RemoteMarkdownSource.isAllowedRemoteURL(url),
                let tokenIndex = arguments.firstIndex(of: "--token-file"),
                arguments.indices.contains(tokenIndex + 1),
                let evidenceIndex = arguments.firstIndex(of: "--evidence-dir"),
                arguments.indices.contains(evidenceIndex + 1)
            else {
                throw VerificationError(
                    "Usage: Aviv --verify-remote-live HTTPS_URL --token-file PATH --evidence-dir PATH"
                )
            }
            self.url = url
            self.tokenFile = URL(fileURLWithPath: arguments[tokenIndex + 1])
            self.evidenceDirectory = URL(fileURLWithPath: arguments[evidenceIndex + 1])
        }
    }
}

private final class FixedRemoteWriteCredentialStore: RemoteWriteCredentialStoring {
    private let fixedToken: String

    init(token: String) {
        fixedToken = token
    }

    func token(for sourceID: String) throws -> String? {
        fixedToken
    }

    func store(token: String, for sourceID: String) throws {}

    func removeToken(for sourceID: String) throws {}
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
