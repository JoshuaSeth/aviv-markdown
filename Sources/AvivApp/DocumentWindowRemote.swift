import AppKit
import AvivCore

@MainActor
extension DocumentWindowController {
    @objc func openRemoteDocument(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }

        let input = NSTextField(string: "")
        input.placeholderString = "https://example.com/document.md"
        input.frame = NSRect(x: 0, y: 0, width: 430, height: 24)
        input.setAccessibilityIdentifier("aviv.remote-open.url")
        input.setAccessibilityLabel("Live document URL")
        input.setAccessibilityHelp(
            "HTTPS address of a public Markdown document that Aviv should open and monitor for changes."
        )

        let alert = NSAlert()
        alert.messageText = "Open Markdown from URL"
        alert.informativeText =
            "Paste a public HTTPS Markdown URL. Aviv will watch it for external edits every second."
        alert.accessoryView = input
        let openButton = alert.addButton(withTitle: "Open")
        openButton.setAccessibilityIdentifier("aviv.remote-open.confirm")
        openButton.setAccessibilityHelp("Opens and begins monitoring the live Markdown document.")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.setAccessibilityIdentifier("aviv.remote-open.cancel")
        cancelButton.setAccessibilityHelp("Closes this dialog without opening a live document.")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value) else {
            presentError(RemoteMarkdownError.insecureURL)
            return
        }
        Task { [weak self] in
            _ = await self?.openRemote(url: url)
        }
    }

    @discardableResult
    func openRemote(url: URL) async -> Bool {
        guard RemoteMarkdownSource.isAllowedRemoteURL(url) else {
            presentError(RemoteMarkdownError.insecureURL)
            return false
        }

        remoteOpenGeneration &+= 1
        let openingGeneration = remoteOpenGeneration
        remoteOpeningController?.stop()
        let previousController = remoteSyncController
        let previousSource = remoteSource
        let controller = RemoteDocumentSyncController(transport: remoteTransport)
        remoteOpeningController = controller
        remoteOpeningURL = url
        controller.markdownStateProvider = { [weak self] in
            guard let self else { return ("", "") }
            return (workspace.textView.string, savedText)
        }
        controller.onOutcome = { [weak self, weak controller] outcome in
            guard let self, let controller, shouldHandleRemoteCallbacks(from: controller)
            else { return }
            handleRemotePollOutcome(outcome)
        }
        controller.onPresentation = { [weak self, weak controller] presentation in
            guard let self, let controller, shouldHandleRemoteCallbacks(from: controller)
            else { return }
            workspace.updateRemoteSyncPresentation(presentation)
        }
        controller.onPollingError = { error in
            NSLog("Aviv remote sync error: %@", error.localizedDescription)
        }
        do {
            let snapshot = try await controller.open(url: url)
            guard remoteOpenGeneration == openingGeneration,
                remoteOpeningController === controller
            else {
                controller.stop()
                return false
            }
            remoteOpeningController = nil
            remoteOpeningURL = nil
            previousController?.stop()
            remoteSyncController = controller
            remoteSource = snapshot.source
            hasPendingRemoteConflict = false
            documentURL = snapshot.source.openedURL
            savedText = snapshot.markdown
            workspace.setDocumentURL(snapshot.source.openedURL)
            workspace.loadMarkdown(snapshot.markdown)
            isEdited = false
            window?.representedURL = snapshot.source.openedURL
            updateWindowTitle()
            workspace.textView.window?.makeFirstResponder(workspace.textView)
            onDocumentURLAccessed?(snapshot.source.openedURL)
            return true
        } catch {
            controller.stop()
            guard remoteOpenGeneration == openingGeneration,
                remoteOpeningController === controller
            else { return false }
            remoteOpeningController = nil
            remoteOpeningURL = nil
            if let previousSource {
                workspace.updateRemoteSyncPresentation(
                    RemoteSyncPresentation(
                        phase: previousSource.isWritable ? .watching : .readOnly,
                        sourceHost: previousSource.displayHost,
                        isWritable: previousSource.isWritable,
                        detail: previousSource.isWritable
                            ? "Live • Save enabled" : "Live • Read-only"
                    )
                )
            } else {
                workspace.updateRemoteSyncPresentation(nil)
            }
            presentError(error)
            return false
        }
    }

    func pollRemoteNow() async {
        await remoteSyncController?.pollNow()
    }

    func saveRemoteDocument(replacingPendingIncoming: Bool = false) async {
        guard let controller = remoteSyncController,
            let source = await controller.currentSource()
        else {
            presentError(RemoteMarkdownError.invalidResponse)
            return
        }
        guard source.isWritable else {
            presentError(RemoteMarkdownError.readOnly)
            return
        }

        if !replacingPendingIncoming,
            await controller.pendingIncomingSnapshot() != nil
        {
            resolveRemoteChanges(nil)
            return
        }

        do {
            guard var token = try credential(for: source) else { return }
            let markdown = workspace.textView.string
            let snapshot: RemoteMarkdownSnapshot
            do {
                snapshot = try await controller.save(
                    markdown: markdown,
                    bearerToken: token,
                    replacingPendingIncoming: replacingPendingIncoming
                )
            } catch let error as RemoteMarkdownError
                where error == .unexpectedStatus(401)
            {
                try remoteCredentialStore.removeToken(for: remoteCredentialKey(for: source))
                guard let refreshedToken = try credential(for: source, forcePrompt: true) else {
                    return
                }
                token = refreshedToken
                snapshot = try await controller.save(
                    markdown: markdown,
                    bearerToken: token,
                    replacingPendingIncoming: replacingPendingIncoming
                )
            }
            remoteSource = snapshot.source
            savedText = snapshot.markdown
            hasPendingRemoteConflict = false
            isEdited = false
            workspace.announceRemoteChange(
                lineRanges: [],
                message: "Saved securely to source"
            )
        } catch {
            if error as? RemoteMarkdownError == .writeConflict {
                await controller.pollNow()
            }
            presentError(error)
        }
    }

    @objc func resolveRemoteChanges(_ sender: Any?) {
        guard let controller = remoteSyncController else { return }
        Task { [weak self] in
            guard let self, let pending = await controller.pendingIncomingSnapshot() else {
                return
            }
            let alert = makeRemoteConflictAlert()
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                await acceptIncoming(pending, controller: controller)
            } else if response == .alertSecondButtonReturn {
                await saveRemoteDocument(replacingPendingIncoming: true)
            }
        }
    }

    func makeRemoteConflictAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Incoming edits are waiting"
        alert.informativeText =
            "Your local edits are untouched. Use the incoming version, replace the remote version with yours, or keep editing."
        alert.window.setAccessibilityIdentifier("aviv.remote-conflict.dialog")
        alert.window.setAccessibilityLabel("Remote document conflict")
        alert.window.setAccessibilityHelp(
            "Resolve the incoming remote Markdown version without losing the current local edits."
        )
        alert.window.setAccessibilityEnabled(true)
        let useIncomingButton = alert.addButton(withTitle: "Use Incoming")
        useIncomingButton.setAccessibilityIdentifier("aviv.remote-conflict.use-incoming")
        useIncomingButton.setAccessibilityHelp(
            "Replaces the local editor contents with the incoming remote document."
        )
        let replaceRemoteButton = alert.addButton(withTitle: "Replace Remote with Mine")
        replaceRemoteButton.setAccessibilityIdentifier("aviv.remote-conflict.replace-remote")
        replaceRemoteButton.setAccessibilityHelp(
            "Keeps the local editor contents and writes them over the pending remote version."
        )
        let keepEditingButton = alert.addButton(withTitle: "Keep Editing")
        keepEditingButton.setAccessibilityIdentifier("aviv.remote-conflict.keep-editing")
        keepEditingButton.setAccessibilityHelp(
            "Leaves both versions pending and returns focus to the local document editor."
        )
        return alert
    }

    func stopRemoteSync() {
        remoteOpenGeneration &+= 1
        remoteOpeningController?.stop()
        remoteOpeningController = nil
        remoteOpeningURL = nil
        remoteSyncController?.stop()
        remoteSyncController = nil
        remoteSource = nil
        lastExternalUpdateResult = nil
        hasPendingRemoteConflict = false
        workspace.updateRemoteSyncPresentation(nil)
    }

    private func shouldHandleRemoteCallbacks(
        from controller: RemoteDocumentSyncController
    ) -> Bool {
        if let remoteOpeningController {
            return remoteOpeningController === controller
        }
        return remoteSyncController === controller
    }

    private func handleRemotePollOutcome(_ outcome: RemoteMarkdownPollOutcome) {
        switch outcome {
        case .unchanged(let source):
            remoteSource = source
        case .apply(let snapshot, let plan):
            remoteSource = snapshot.source
            hasPendingRemoteConflict = false
            documentURL = snapshot.source.openedURL
            savedText = snapshot.markdown
            lastExternalUpdateResult = workspace.applyExternalMarkdown(
                snapshot.markdown,
                using: plan
            )
            isEdited = false
            workspace.announceRemoteChange(
                lineRanges: plan.changedLineRanges(in: snapshot.markdown),
                message: "External edits applied"
            )
        case .conflict(let snapshot, let plan):
            remoteSource = snapshot.source
            hasPendingRemoteConflict = true
            workspace.announceRemoteChange(
                lineRanges: plan.changedOldLineRanges(in: workspace.textView.string),
                message: "Incoming edits waiting — local work preserved",
                conflict: true
            )
        }
    }

    private func acceptIncoming(
        _ pending: RemoteMarkdownSnapshot,
        controller: RemoteDocumentSyncController
    ) async {
        do {
            let current = workspace.textView.string
            let plan = RemoteMarkdownChangePlan(
                oldMarkdown: current,
                newMarkdown: pending.markdown
            )
            let accepted = try await controller.acceptPendingIncoming()
            remoteSource = accepted.source
            savedText = accepted.markdown
            hasPendingRemoteConflict = false
            lastExternalUpdateResult = workspace.applyExternalMarkdown(
                accepted.markdown,
                using: plan
            )
            isEdited = false
            workspace.announceRemoteChange(
                lineRanges: plan.changedLineRanges(in: accepted.markdown),
                message: "Incoming edits accepted"
            )
        } catch {
            presentError(error)
        }
    }

    private func credential(
        for source: RemoteMarkdownSource,
        forcePrompt: Bool = false
    ) throws -> String? {
        let credentialKey = remoteCredentialKey(for: source)
        if !forcePrompt, let stored = try remoteCredentialStore.token(for: credentialKey) {
            return stored
        }

        let input = NSSecureTextField(string: "")
        input.placeholderString = "Write token"
        input.frame = NSRect(x: 0, y: 0, width: 380, height: 24)
        input.setAccessibilityIdentifier("aviv.remote-save.credential")
        input.setAccessibilityLabel("Remote write credential")
        input.setAccessibilityHelp(
            "Write token for the remote Markdown source. The value is stored in macOS Keychain."
        )
        let alert = NSAlert()
        alert.messageText = "Authenticate remote save"
        let writeHost =
            source.writeURL?.host(percentEncoded: false)
            ?? source.writeURL?.host
            ?? source.displayHost
        alert.informativeText =
            "Enter the write token for \(writeHost). Aviv stores it in your macOS Keychain and never puts it in the URL."
        alert.accessoryView = input
        let saveCredentialButton = alert.addButton(withTitle: "Save Credential")
        saveCredentialButton.setAccessibilityIdentifier("aviv.remote-save.credential-confirm")
        saveCredentialButton.setAccessibilityHelp(
            "Stores the credential in macOS Keychain and continues the remote save."
        )
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.setAccessibilityIdentifier("aviv.remote-save.credential-cancel")
        cancelButton.setAccessibilityHelp("Cancels the remote save without storing a credential.")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw RemoteMarkdownError.missingCredential
        }
        try remoteCredentialStore.store(token: token, for: credentialKey)
        return token
    }

    private func remoteCredentialKey(for source: RemoteMarkdownSource) -> String {
        guard let writeURL = source.writeURL else { return source.sourceID }
        var origin = "\(writeURL.scheme ?? "https")://\(writeURL.host ?? "unknown")"
        if let port = writeURL.port {
            origin += ":\(port)"
        }
        return "\(source.sourceID)|\(origin)"
    }
}
