import Foundation
import XCTest

@testable import AvivCore

final class RemoteMarkdownSessionTests: XCTestCase {
    func testOpenPreservesPublicAndEditableSourceIdentity() async throws {
        let initial = try snapshot(markdown: "# Initial", etag: "\"v1\"")
        let transport = StubRemoteMarkdownTransport(fetchResults: [.document(initial)])
        let session = try await RemoteMarkdownSession.open(
            url: initial.source.openedURL,
            transport: transport
        )
        let opened = await session.initialSnapshot()

        XCTAssertEqual(opened, initial)
        XCTAssertEqual(opened.source.sourceID, "seth-demo")
        XCTAssertEqual(opened.source.writeURL?.path, "/api/aviv-live/seth-demo.md")
        XCTAssertTrue(opened.source.isWritable)
    }

    func testCleanPollAppliesIncomingChange() async throws {
        let initial = try snapshot(markdown: "# Initial", etag: "\"v1\"")
        let incoming = try snapshot(markdown: "# Initial\n\nAgent update", etag: "\"v2\"")
        let transport = StubRemoteMarkdownTransport(
            fetchResults: [.document(initial), .document(incoming)]
        )
        let session = try await RemoteMarkdownSession.open(
            url: initial.source.openedURL,
            transport: transport
        )
        let outcome = try await session.poll(
            localMarkdown: initial.markdown,
            savedMarkdown: initial.markdown
        )

        guard case .apply(let snapshot, let plan) = outcome else {
            return XCTFail("Expected a clean incoming update to apply")
        }
        XCTAssertEqual(snapshot, incoming)
        XCTAssertTrue(plan.hasChanges)
        let pending = await session.pendingIncomingSnapshot()
        XCTAssertNil(pending)
    }

    func testDirtyPollPreservesLocalTextAndRecordsConflict() async throws {
        let initial = try snapshot(markdown: "# Initial", etag: "\"v1\"")
        let incoming = try snapshot(markdown: "# Initial\n\nAgent update", etag: "\"v2\"")
        let transport = StubRemoteMarkdownTransport(
            fetchResults: [.document(initial), .document(incoming)]
        )
        let session = try await RemoteMarkdownSession.open(
            url: initial.source.openedURL,
            transport: transport
        )
        let local = "# Initial\n\nSeth edit"
        let outcome = try await session.poll(
            localMarkdown: local,
            savedMarkdown: initial.markdown
        )

        guard case .conflict(let snapshot, _) = outcome else {
            return XCTFail("Expected simultaneous edits to create a conflict")
        }
        XCTAssertEqual(snapshot, incoming)
        XCTAssertEqual(local, "# Initial\n\nSeth edit")
        let pending = await session.pendingIncomingSnapshot()
        XCTAssertEqual(pending, incoming)
    }

    func testSaveRefusesPendingConflictThenAllowsExplicitReplacement() async throws {
        let initial = try snapshot(markdown: "# Initial", etag: "\"v1\"")
        let incoming = try snapshot(markdown: "# Agent", etag: "\"v2\"")
        let savedSource = try source(etag: "\"v3\"")
        let transport = StubRemoteMarkdownTransport(
            fetchResults: [.document(initial), .document(incoming)],
            saveSource: savedSource
        )
        let session = try await RemoteMarkdownSession.open(
            url: initial.source.openedURL,
            transport: transport
        )
        _ = try await session.poll(localMarkdown: "# Seth", savedMarkdown: initial.markdown)

        do {
            _ = try await session.save(markdown: "# Seth", bearerToken: "credential")
            XCTFail("Save must not overwrite an unresolved incoming change")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .incomingConflict)
        }

        let saved = try await session.save(
            markdown: "# Seth",
            bearerToken: "credential",
            replacingPendingIncoming: true
        )
        XCTAssertEqual(saved.markdown, "# Seth")
        XCTAssertEqual(saved.source.validator.etag, "\"v3\"")
        let calls = await transport.recordedSaves()
        XCTAssertEqual(
            calls,
            [StubRemoteMarkdownTransport.SaveCall(markdown: "# Seth", etag: "\"v2\"")]
        )
    }

    func testPollingIntervalIsClampedToOneSecond() throws {
        let remote = try RemoteMarkdownSource(
            openedURL: URL(string: "https://pitchai.net/aviv-live/seth-demo.md")!,
            resolvedURL: URL(string: "https://pitchai.net/aviv-live/seth-demo.md")!,
            sourceID: "seth-demo",
            writeURL: nil,
            pollingInterval: 0.05,
            validator: RemoteMarkdownValidator(etag: nil, lastModified: nil)
        )

        XCTAssertEqual(remote.pollingInterval, 1)
    }

    func testRejectsCredentialBearingOrInsecureURLs() {
        XCTAssertFalse(
            RemoteMarkdownSource.isAllowedRemoteURL(
                URL(string: "https://token@example.com/private.md")!
            )
        )
        XCTAssertFalse(
            RemoteMarkdownSource.isAllowedRemoteURL(URL(string: "http://example.com/file.md")!)
        )
    }

    func testSourceRejectsControlCharactersInIdentity() throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        XCTAssertThrowsError(
            try RemoteMarkdownSource(
                openedURL: url,
                resolvedURL: url,
                sourceID: "source\nforged-header",
                writeURL: nil,
                pollingInterval: 1,
                validator: RemoteMarkdownValidator(etag: nil, lastModified: nil)
            )
        ) { error in
            XCTAssertEqual(error as? RemoteMarkdownError, .missingSourceIdentity)
        }
    }

    private func snapshot(markdown: String, etag: String) throws -> RemoteMarkdownSnapshot {
        RemoteMarkdownSnapshot(markdown: markdown, source: try source(etag: etag))
    }

    private func source(etag: String) throws -> RemoteMarkdownSource {
        try RemoteMarkdownSource(
            openedURL: URL(string: "https://pitchai.net/aviv-live/seth-demo.md")!,
            resolvedURL: URL(string: "https://pitchai.net/aviv-live/seth-demo.md")!,
            sourceID: "seth-demo",
            writeURL: URL(string: "https://pitchai.net/api/aviv-live/seth-demo.md")!,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: etag, lastModified: nil)
        )
    }
}

private actor StubRemoteMarkdownTransport: RemoteMarkdownTransport {
    struct SaveCall: Equatable, Sendable {
        let markdown: String
        let etag: String?
    }

    private var fetchResults: [RemoteMarkdownFetchResult]
    private let saveSource: RemoteMarkdownSource?
    private var saves: [SaveCall] = []

    init(
        fetchResults: [RemoteMarkdownFetchResult],
        saveSource: RemoteMarkdownSource? = nil
    ) {
        self.fetchResults = fetchResults
        self.saveSource = saveSource
    }

    func fetch(
        from url: URL,
        openedURL: URL,
        validator: RemoteMarkdownValidator?
    ) throws -> RemoteMarkdownFetchResult {
        guard !fetchResults.isEmpty else {
            return .notModified
        }
        return fetchResults.removeFirst()
    }

    func save(
        markdown: String,
        to source: RemoteMarkdownSource,
        bearerToken: String
    ) throws -> RemoteMarkdownSource {
        saves.append(SaveCall(markdown: markdown, etag: source.validator.etag))
        guard bearerToken == "credential" else {
            throw RemoteMarkdownError.missingCredential
        }
        return saveSource ?? source
    }

    func recordedSaves() -> [SaveCall] {
        saves
    }
}
