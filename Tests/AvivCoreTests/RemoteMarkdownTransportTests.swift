import Foundation
import XCTest

@testable import AvivCore

final class RemoteMarkdownTransportTests: XCTestCase {
    func testFetchReadsSourceContractAndSendsConditionalValidator() async throws {
        let openedURL = try XCTUnwrap(URL(string: "https://public.example/fetch.md"))
        let resolvedURL = try XCTUnwrap(URL(string: "https://cdn.example/fetch.md"))
        let writeURL = try XCTUnwrap(URL(string: "https://bridge.example/api/fetch.md"))
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
        let publicURL = try XCTUnwrap(URL(string: "https://public.example/save.md"))
        let writeURL = try XCTUnwrap(URL(string: "https://bridge.example/api/save.md"))
        let source = try RemoteMarkdownSource(
            openedURL: publicURL,
            resolvedURL: publicURL,
            sourceID: "seth-live-demo",
            writeURL: writeURL,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"v1\"", lastModified: nil)
        )
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
        let url = try XCTUnwrap(URL(string: "https://public.example/precondition.md"))
        let source = try RemoteMarkdownSource(
            openedURL: url,
            resolvedURL: url,
            sourceID: "seth-live-demo",
            writeURL: url,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"stale\"", lastModified: nil)
        )
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
        let url = try XCTUnwrap(URL(string: "https://public.example/identity-conflict.md"))
        let source = try RemoteMarkdownSource(
            openedURL: url,
            resolvedURL: url,
            sourceID: "seth-live-demo",
            writeURL: url,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"v1\"", lastModified: nil)
        )
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
        let url = try XCTUnwrap(URL(string: "https://public.example/missing-write-etag.md"))
        let source = try RemoteMarkdownSource(
            openedURL: url,
            resolvedURL: url,
            sourceID: "seth-live-demo",
            writeURL: url,
            pollingInterval: 1,
            validator: RemoteMarkdownValidator(etag: "\"v1\"", lastModified: nil)
        )
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
        let url = try XCTUnwrap(URL(string: "https://public.example/writable-without-etag.md"))

        do {
            _ = try await makeTransport().fetch(from: url, openedURL: url, validator: nil)
            XCTFail("Expected a writable source without an ETag to fail loudly")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .missingWriteValidator)
        }
    }

    func testFetchRejectsNonFinitePollingInterval() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/invalid-poll-interval.md"))

        do {
            _ = try await makeTransport().fetch(from: url, openedURL: url, validator: nil)
            XCTFail("Expected a non-finite polling interval to fail loudly")
        } catch {
            XCTAssertEqual(error as? RemoteMarkdownError, .invalidPollingInterval)
        }
    }

    func testFetchRejectsInsecureAdvertisedWriteURL() async throws {
        let url = try XCTUnwrap(URL(string: "https://public.example/insecure-write-url.md"))

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
}

private final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url else {
            throw RemoteMarkdownError.invalidResponse
        }
        switch url.path {
        case "/fetch.md":
            return try fetchResponse(for: request, url: url)
        case "/api/save.md":
            return try saveResponse(for: request, url: url)
        case "/precondition.md":
            return try response(url: url, statusCode: 412)
        case "/identity-conflict.md":
            return try response(url: url, statusCode: 409)
        case "/missing-write-etag.md":
            return try response(url: url, statusCode: 204)
        case "/writable-without-etag.md":
            return try response(
                url: url,
                statusCode: 200,
                headers: [
                    "X-Aviv-Source-ID": "seth-live-demo",
                    "X-Aviv-Write-URL": "https://bridge.example/api/writable-without-etag.md",
                ],
                data: Data("# Remote\n".utf8)
            )
        case "/invalid-poll-interval.md":
            return try response(
                url: url,
                statusCode: 200,
                headers: ["X-Aviv-Poll-Interval": "nan"],
                data: Data("# Remote\n".utf8)
            )
        case "/insecure-write-url.md":
            return try response(
                url: url,
                statusCode: 200,
                headers: [
                    "ETag": "\"v1\"",
                    "X-Aviv-Write-URL": "http://bridge.example/api/insecure-write-url.md",
                ],
                data: Data("# Remote\n".utf8)
            )
        default:
            throw RemoteMarkdownError.invalidResponse
        }
    }

    private static func fetchResponse(
        for request: URLRequest,
        url: URL
    ) throws -> (HTTPURLResponse, Data) {
        if url.host == "cdn.example" {
            guard request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" else {
                throw RemoteMarkdownError.invalidResponse
            }
            return try response(url: url, statusCode: 304)
        }
        guard url.host == "public.example",
            let resolvedURL = URL(string: "https://cdn.example/fetch.md")
        else {
            throw RemoteMarkdownError.invalidResponse
        }
        return try response(
            url: resolvedURL,
            statusCode: 200,
            headers: [
                "Content-Type": "text/markdown; charset=utf-8",
                "ETag": "\"v1\"",
                "X-Aviv-Source-ID": "seth-live-demo",
                "X-Aviv-Write-URL": "https://bridge.example/api/fetch.md",
                "X-Aviv-Poll-Interval": "0.2",
            ],
            data: Data("# Remote\n".utf8)
        )
    }

    private static func saveResponse(
        for request: URLRequest,
        url: URL
    ) throws -> (HTTPURLResponse, Data) {
        guard request.httpMethod == "PUT",
            request.value(forHTTPHeaderField: "Authorization") == "Bearer secret",
            request.value(forHTTPHeaderField: "If-Match") == "\"v1\"",
            request.value(forHTTPHeaderField: "X-Aviv-Source-ID") == "seth-live-demo",
            requestBody(request) == Data("# Saved\n".utf8)
        else {
            throw RemoteMarkdownError.invalidResponse
        }
        return try response(
            url: url,
            statusCode: 204,
            headers: [
                "ETag": "\"v2\"",
                "X-Aviv-Source-ID": "seth-live-demo",
                "X-Aviv-Write-URL": "https://bridge.example/api/save.md",
            ]
        )
    }

    private static func response(
        url: URL,
        statusCode: Int,
        headers: [String: String]? = nil,
        data: Data = Data()
    ) throws -> (HTTPURLResponse, Data) {
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            throw RemoteMarkdownError.invalidResponse
        }
        return (response, data)
    }

    private static func requestBody(_ request: URLRequest) -> Data? {
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
