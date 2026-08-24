import Foundation
import XCTest

@testable import AvivCore

final class RemoteMarkdownTransportTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchReadsSourceContractAndSendsConditionalValidator() async throws {
        let openedURL = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        let resolvedURL = try XCTUnwrap(URL(string: "https://cdn.example/live.md"))
        let writeURL = try XCTUnwrap(URL(string: "https://bridge.example/api/live.md"))
        var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 2 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
                return (
                    try XCTUnwrap(
                        HTTPURLResponse(
                            url: resolvedURL,
                            statusCode: 304,
                            httpVersion: "HTTP/1.1",
                            headerFields: nil
                        )
                    ),
                    Data()
                )
            }
            return (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: resolvedURL,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Type": "text/markdown; charset=utf-8",
                            "ETag": "\"v1\"",
                            "X-Aviv-Source-ID": "seth-live-demo",
                            "X-Aviv-Write-URL": writeURL.absoluteString,
                            "X-Aviv-Poll-Interval": "0.2",
                        ]
                    )
                ),
                Data("# Remote\n".utf8)
            )
        }
        let transport = makeTransport()

        let first = try await transport.fetch(from: openedURL, openedURL: openedURL, validator: nil)
        guard case .document(let snapshot) = first else {
            return XCTFail("Expected the first fetch to return Markdown")
        }
        XCTAssertEqual(snapshot.markdown, "# Remote\n")
        XCTAssertEqual(snapshot.source.openedURL, openedURL)
        XCTAssertEqual(snapshot.source.resolvedURL, resolvedURL)
        XCTAssertEqual(snapshot.source.sourceID, "seth-live-demo")
        XCTAssertEqual(snapshot.source.writeURL, writeURL)
        XCTAssertEqual(snapshot.source.pollingInterval, 1)

        let second = try await transport.fetch(
            from: snapshot.source.resolvedURL,
            openedURL: openedURL,
            validator: snapshot.source.validator
        )
        XCTAssertEqual(second, .notModified)
    }

    func testSaveUsesBearerAndIfMatchWithoutChangingPollingURL() async throws {
        let publicURL = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        let writeURL = try XCTUnwrap(URL(string: "https://bridge.example/api/live.md"))
        let source = try RemoteMarkdownSource(
            openedURL: publicURL,
            resolvedURL: publicURL,
            sourceID: "seth-live-demo",
            writeURL: writeURL,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"v1\"", lastModified: nil)
        )
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url, writeURL)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"v1\"")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Aviv-Source-ID"),
                "seth-live-demo"
            )
            XCTAssertEqual(self.requestBody(request), Data("# Saved\n".utf8))
            return (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: writeURL,
                        statusCode: 204,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "ETag": "\"v2\"",
                            "X-Aviv-Source-ID": "seth-live-demo",
                            "X-Aviv-Write-URL": writeURL.absoluteString,
                        ]
                    )
                ),
                Data()
            )
        }

        let updated = try await makeTransport().save(
            markdown: "# Saved\n",
            to: source,
            bearerToken: "secret"
        )
        XCTAssertEqual(updated.resolvedURL, publicURL)
        XCTAssertEqual(updated.validator.etag, "\"v2\"")
        XCTAssertEqual(updated.writeURL, writeURL)
    }

    func testSaveMapsPreconditionFailureToWriteConflict() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        let source = try RemoteMarkdownSource(
            openedURL: url,
            resolvedURL: url,
            sourceID: "seth-live-demo",
            writeURL: url,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"stale\"", lastModified: nil)
        )
        StubURLProtocol.handler = { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 412,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )
                ),
                Data()
            )
        }

        do {
            _ = try await makeTransport().save(
                markdown: "local",
                to: source,
                bearerToken: "secret"
            )
            XCTFail("Expected a conflict")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .writeConflict)
        }
    }

    func testSaveMapsIdentityConflictToSourceIdentityChange() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        let source = try RemoteMarkdownSource(
            openedURL: url,
            resolvedURL: url,
            sourceID: "seth-live-demo",
            writeURL: url,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"v1\"", lastModified: nil)
        )
        StubURLProtocol.handler = { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 409,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )
                ),
                Data()
            )
        }

        do {
            _ = try await makeTransport().save(
                markdown: "local",
                to: source,
                bearerToken: "secret"
            )
            XCTFail("Expected the source identity change to fail loudly")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .sourceIdentityChanged)
        }
    }

    func testSaveRequiresFreshETagFromWriteResponse() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        let source = try RemoteMarkdownSource(
            openedURL: url,
            resolvedURL: url,
            sourceID: "seth-live-demo",
            writeURL: url,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"v1\"", lastModified: nil)
        )
        StubURLProtocol.handler = { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 204,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )
                ),
                Data()
            )
        }

        do {
            _ = try await makeTransport().save(
                markdown: "local",
                to: source,
                bearerToken: "secret"
            )
            XCTFail("Expected a fresh validator to be required")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .missingWriteValidator)
        }
    }

    func testFetchRejectsWritableContractWithoutETag() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        StubURLProtocol.handler = { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "X-Aviv-Source-ID": "seth-live-demo",
                            "X-Aviv-Write-URL": "https://bridge.example/api/live.md",
                        ]
                    )
                ),
                Data("# Remote\n".utf8)
            )
        }

        do {
            _ = try await makeTransport().fetch(from: url, openedURL: url, validator: nil)
            XCTFail("Expected a writable source without an ETag to fail loudly")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .missingWriteValidator)
        }
    }

    func testFetchRejectsNonFinitePollingInterval() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        StubURLProtocol.handler = { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["X-Aviv-Poll-Interval": "nan"]
                    )
                ),
                Data("# Remote\n".utf8)
            )
        }

        do {
            _ = try await makeTransport().fetch(from: url, openedURL: url, validator: nil)
            XCTFail("Expected a non-finite polling interval to fail loudly")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .invalidPollingInterval)
        }
    }

    func testFetchRejectsInsecureAdvertisedWriteURL() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/live.md"))
        StubURLProtocol.handler = { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "ETag": "\"v1\"",
                            "X-Aviv-Write-URL": "http://bridge.example/api/live.md",
                        ]
                    )
                ),
                Data("# Remote\n".utf8)
            )
        }

        do {
            _ = try await makeTransport().fetch(from: url, openedURL: url, validator: nil)
            XCTFail("Expected an insecure write URL to fail loudly")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .insecureWriteURL)
        }
    }

    private func makeTransport() -> URLSessionRemoteMarkdownTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionRemoteMarkdownTransport(session: URLSession(configuration: configuration))
    }

    private func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: RemoteMarkdownError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
