import AvivCore
import Foundation

@MainActor
final class RemoteDocumentSyncController {
    typealias MarkdownState = (current: String, saved: String)

    var markdownStateProvider: (() -> MarkdownState)?
    var onOutcome: ((RemoteMarkdownPollOutcome) -> Void)?
    var onPresentation: ((RemoteSyncPresentation) -> Void)?
    var onPollingError: ((Error) -> Void)?

    private let transport: any RemoteMarkdownTransport
    private var session: RemoteMarkdownSession?
    private var pollingTask: Task<Void, Never>?
    private var operationInFlight = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private var lifecycleGeneration: UInt64 = 0

    init(transport: any RemoteMarkdownTransport) {
        self.transport = transport
    }

    var isActive: Bool {
        session != nil
    }

    func open(url: URL) async throws -> RemoteMarkdownSnapshot {
        stop()
        let openingGeneration = lifecycleGeneration
        present(
            phase: .connecting,
            sourceHost: url.host(percentEncoded: false) ?? url.host ?? "Remote source",
            isWritable: false,
            detail: "Connecting…"
        )
        let openedSession = try await RemoteMarkdownSession.open(url: url, transport: transport)
        guard lifecycleGeneration == openingGeneration else {
            throw CancellationError()
        }
        session = openedSession
        let snapshot = await openedSession.initialSnapshot()
        presentWatching(
            snapshot.source,
            detail: snapshot.source.isWritable ? "Live • Save enabled" : "Live • Read-only"
        )
        startPolling(interval: snapshot.source.pollingInterval)
        return snapshot
    }

    func pollNow() async {
        guard let session, !operationInFlight, let state = markdownStateProvider?() else { return }
        operationInFlight = true
        defer { releaseOperation() }
        let source = await session.currentSource()
        present(
            phase: .checking,
            sourceHost: source.displayHost,
            isWritable: source.isWritable,
            detail: "Checking for edits…"
        )
        do {
            let outcome = try await session.poll(
                localMarkdown: state.current,
                savedMarkdown: state.saved
            )
            guard self.session === session else { return }
            onOutcome?(outcome)
            let currentSource = await session.currentSource()
            switch outcome {
            case .unchanged:
                presentWatching(currentSource, detail: "Live • Up to date")
            case .apply:
                present(
                    phase: .incomingApplied,
                    sourceHost: currentSource.displayHost,
                    isWritable: currentSource.isWritable,
                    detail: "External edit applied"
                )
            case .conflict:
                present(
                    phase: .conflict,
                    sourceHost: currentSource.displayHost,
                    isWritable: currentSource.isWritable,
                    detail: "Incoming edit waiting"
                )
            }
        } catch {
            guard self.session === session else { return }
            present(
                phase: .error,
                sourceHost: source.displayHost,
                isWritable: source.isWritable,
                detail: "Sync paused"
            )
            onPollingError?(error)
        }
    }

    func save(
        markdown: String,
        bearerToken: String,
        replacingPendingIncoming: Bool = false
    ) async throws -> RemoteMarkdownSnapshot {
        guard let session else {
            throw RemoteMarkdownError.invalidResponse
        }
        await acquireOperation()
        defer { releaseOperation() }
        guard self.session === session else {
            throw RemoteMarkdownError.invalidResponse
        }
        let source = await session.currentSource()
        present(
            phase: .saving,
            sourceHost: source.displayHost,
            isWritable: source.isWritable,
            detail: "Saving securely…"
        )
        do {
            let snapshot = try await session.save(
                markdown: markdown,
                bearerToken: bearerToken,
                replacingPendingIncoming: replacingPendingIncoming
            )
            present(
                phase: .saved,
                sourceHost: snapshot.source.displayHost,
                isWritable: true,
                detail: "Saved to source"
            )
            return snapshot
        } catch {
            let latestSource = await session.currentSource()
            present(
                phase: error as? RemoteMarkdownError == .incomingConflict ? .conflict : .error,
                sourceHost: latestSource.displayHost,
                isWritable: latestSource.isWritable,
                detail: error as? RemoteMarkdownError == .incomingConflict
                    ? "Incoming edit waiting" : "Save failed"
            )
            throw error
        }
    }

    func acceptPendingIncoming() async throws -> RemoteMarkdownSnapshot {
        guard let session else {
            throw RemoteMarkdownError.invalidResponse
        }
        await acquireOperation()
        defer { releaseOperation() }
        guard self.session === session else {
            throw RemoteMarkdownError.invalidResponse
        }
        let snapshot = try await session.acceptPendingIncoming()
        presentWatching(snapshot.source, detail: "Live • Incoming accepted")
        return snapshot
    }

    func pendingIncomingSnapshot() async -> RemoteMarkdownSnapshot? {
        await session?.pendingIncomingSnapshot()
    }

    func currentSource() async -> RemoteMarkdownSource? {
        await session?.currentSource()
    }

    func stop() {
        lifecycleGeneration &+= 1
        pollingTask?.cancel()
        pollingTask = nil
        session = nil
        if !operationInFlight {
            operationWaiters.removeAll()
        }
    }

    private func startPolling(interval: TimeInterval) {
        pollingTask?.cancel()
        let nanoseconds = UInt64(interval * 1_000_000_000)
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.pollNow()
            }
        }
    }

    private func acquireOperation() async {
        if !operationInFlight {
            operationInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationInFlight = false
            return
        }
        operationWaiters.removeFirst().resume()
    }

    private func presentWatching(_ source: RemoteMarkdownSource, detail: String) {
        present(
            phase: source.isWritable ? .watching : .readOnly,
            sourceHost: source.displayHost,
            isWritable: source.isWritable,
            detail: detail
        )
    }

    private func present(
        phase: RemoteSyncPhase,
        sourceHost: String,
        isWritable: Bool,
        detail: String
    ) {
        onPresentation?(
            RemoteSyncPresentation(
                phase: phase,
                sourceHost: sourceHost,
                isWritable: isWritable,
                detail: detail
            )
        )
    }
}
