import Foundation

public enum RemoteMarkdownPollOutcome: Equatable, Sendable {
    case unchanged(RemoteMarkdownSource)
    case apply(RemoteMarkdownSnapshot, RemoteMarkdownChangePlan)
    case conflict(RemoteMarkdownSnapshot, RemoteMarkdownChangePlan)
}

public actor RemoteMarkdownSession {
    private let transport: any RemoteMarkdownTransport
    private var acceptedMarkdown: String
    private var observedMarkdown: String
    private var source: RemoteMarkdownSource
    private var pendingSnapshot: RemoteMarkdownSnapshot?

    private init(
        transport: any RemoteMarkdownTransport,
        snapshot: RemoteMarkdownSnapshot
    ) {
        self.transport = transport
        acceptedMarkdown = snapshot.markdown
        observedMarkdown = snapshot.markdown
        source = snapshot.source
    }

    public static func open(
        url: URL,
        transport: any RemoteMarkdownTransport = URLSessionRemoteMarkdownTransport()
    ) async throws -> RemoteMarkdownSession {
        let result = try await transport.fetch(from: url, openedURL: url, validator: nil)
        guard case .document(let snapshot) = result else {
            throw RemoteMarkdownError.invalidResponse
        }
        return RemoteMarkdownSession(transport: transport, snapshot: snapshot)
    }

    public func initialSnapshot() -> RemoteMarkdownSnapshot {
        RemoteMarkdownSnapshot(markdown: acceptedMarkdown, source: source)
    }

    public func currentSource() -> RemoteMarkdownSource {
        source
    }

    public func pendingIncomingSnapshot() -> RemoteMarkdownSnapshot? {
        pendingSnapshot
    }

    public func poll(
        localMarkdown: String,
        savedMarkdown: String
    ) async throws -> RemoteMarkdownPollOutcome {
        let result = try await transport.fetch(
            from: source.resolvedURL,
            openedURL: source.openedURL,
            validator: source.validator
        )
        guard case .document(let snapshot) = result else {
            return .unchanged(source)
        }
        guard snapshot.source.sourceID == source.sourceID else {
            throw RemoteMarkdownError.sourceIdentityChanged
        }
        source = snapshot.source
        if snapshot.markdown == observedMarkdown {
            return .unchanged(source)
        }

        let plan = RemoteMarkdownChangePlan(
            oldMarkdown: acceptedMarkdown,
            newMarkdown: snapshot.markdown
        )
        observedMarkdown = snapshot.markdown
        if localMarkdown == savedMarkdown, savedMarkdown == acceptedMarkdown {
            acceptedMarkdown = snapshot.markdown
            pendingSnapshot = nil
            return .apply(snapshot, plan)
        }

        pendingSnapshot = snapshot
        return .conflict(snapshot, plan)
    }

    public func acceptPendingIncoming() throws -> RemoteMarkdownSnapshot {
        guard let snapshot = pendingSnapshot else {
            throw RemoteMarkdownError.invalidResponse
        }
        acceptedMarkdown = snapshot.markdown
        observedMarkdown = snapshot.markdown
        source = snapshot.source
        pendingSnapshot = nil
        return snapshot
    }

    public func save(
        markdown: String,
        bearerToken: String,
        replacingPendingIncoming: Bool = false
    ) async throws -> RemoteMarkdownSnapshot {
        if pendingSnapshot != nil, !replacingPendingIncoming {
            throw RemoteMarkdownError.incomingConflict
        }
        let updatedSource = try await transport.save(
            markdown: markdown,
            to: source,
            bearerToken: bearerToken
        )
        let snapshot = RemoteMarkdownSnapshot(markdown: markdown, source: updatedSource)
        source = updatedSource
        acceptedMarkdown = markdown
        observedMarkdown = markdown
        pendingSnapshot = nil
        return snapshot
    }
}
