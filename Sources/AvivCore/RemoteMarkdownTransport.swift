import Foundation

public enum RemoteMarkdownFetchResult: Equatable, Sendable {
    case notModified
    case document(RemoteMarkdownSnapshot)
}

public protocol RemoteMarkdownTransport: Sendable {
    func fetch(
        from url: URL,
        openedURL: URL,
        validator: RemoteMarkdownValidator?
    ) async throws -> RemoteMarkdownFetchResult

    func save(
        markdown: String,
        to source: RemoteMarkdownSource,
        bearerToken: String
    ) async throws -> RemoteMarkdownSource
}

public final class URLSessionRemoteMarkdownTransport: RemoteMarkdownTransport, Sendable {
    private static let maximumDocumentBytes = 16 * 1_024 * 1_024
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(
        from url: URL,
        openedURL: URL,
        validator: RemoteMarkdownValidator?
    ) async throws -> RemoteMarkdownFetchResult {
        guard RemoteMarkdownSource.isAllowedRemoteURL(url) else {
            throw RemoteMarkdownError.insecureURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("text/markdown, text/plain;q=0.9", forHTTPHeaderField: "Accept")
        if let etag = validator?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        } else if let lastModified = validator?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteMarkdownError.invalidResponse
        }
        if http.statusCode == 304 {
            return .notModified
        }
        guard http.statusCode == 200 else {
            throw RemoteMarkdownError.unexpectedStatus(http.statusCode)
        }
        guard data.count <= Self.maximumDocumentBytes else {
            throw RemoteMarkdownError.documentTooLarge
        }
        let markdown = try Self.decodeMarkdown(data)
        let source = try Self.source(from: http, openedURL: openedURL)
        return .document(RemoteMarkdownSnapshot(markdown: markdown, source: source))
    }

    public func save(
        markdown: String,
        to source: RemoteMarkdownSource,
        bearerToken: String
    ) async throws -> RemoteMarkdownSource {
        guard let writeURL = source.writeURL else {
            throw RemoteMarkdownError.readOnly
        }
        guard !bearerToken.isEmpty else {
            throw RemoteMarkdownError.missingCredential
        }
        guard let etag = source.validator.etag else {
            throw RemoteMarkdownError.missingWriteValidator
        }
        guard let body = markdown.data(using: .utf8), body.count <= Self.maximumDocumentBytes else {
            throw RemoteMarkdownError.documentTooLarge
        }

        var request = URLRequest(url: writeURL)
        request.httpMethod = "PUT"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(etag, forHTTPHeaderField: "If-Match")
        request.setValue(source.sourceID, forHTTPHeaderField: "X-Aviv-Source-ID")
        request.setValue("text/markdown; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteMarkdownError.invalidResponse
        }
        if http.statusCode == 409 {
            throw RemoteMarkdownError.sourceIdentityChanged
        }
        if http.statusCode == 412 {
            throw RemoteMarkdownError.writeConflict
        }
        guard http.statusCode == 200 || http.statusCode == 204 else {
            throw RemoteMarkdownError.unexpectedStatus(http.statusCode)
        }
        guard
            let responseETag = http.value(forHTTPHeaderField: "ETag")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !responseETag.isEmpty
        else {
            throw RemoteMarkdownError.missingWriteValidator
        }
        return try Self.source(
            from: http,
            openedURL: source.openedURL,
            fallback: source,
            resolvedURLOverride: source.resolvedURL
        )
    }

    private static func decodeMarkdown(_ data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\0") {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16), !utf16.contains("\0") {
            return utf16
        }
        throw RemoteMarkdownError.invalidMarkdownEncoding
    }

    private static func source(
        from response: HTTPURLResponse,
        openedURL: URL,
        fallback: RemoteMarkdownSource? = nil,
        resolvedURLOverride: URL? = nil
    ) throws -> RemoteMarkdownSource {
        guard let resolvedURL = resolvedURLOverride ?? response.url else {
            throw RemoteMarkdownError.invalidResponse
        }
        let sourceID =
            response.value(forHTTPHeaderField: "X-Aviv-Source-ID")
            ?? fallback?.sourceID
            ?? resolvedURL.absoluteString
        let writeHeader = response.value(forHTTPHeaderField: "X-Aviv-Write-URL")
        let writeURL: URL?
        if let writeHeader {
            let trimmedWriteHeader = writeHeader.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedWriteHeader.isEmpty,
                let parsedWriteURL = URL(
                    string: trimmedWriteHeader,
                    relativeTo: resolvedURL
                )?.absoluteURL
            else {
                throw RemoteMarkdownError.insecureWriteURL
            }
            writeURL = parsedWriteURL
        } else {
            writeURL = fallback?.writeURL
        }
        let intervalHeader = response.value(forHTTPHeaderField: "X-Aviv-Poll-Interval")
        let interval: TimeInterval
        if let intervalHeader {
            guard let parsedInterval = TimeInterval(intervalHeader), parsedInterval.isFinite else {
                throw RemoteMarkdownError.invalidPollingInterval
            }
            interval = parsedInterval
        } else {
            interval = fallback?.pollingInterval ?? RemoteMarkdownSource.defaultPollingInterval
        }
        let validator = RemoteMarkdownValidator(
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
        if let fallback {
            return try fallback.updating(
                resolvedURL: resolvedURL,
                sourceID: sourceID,
                writeURL: writeURL,
                pollingInterval: interval,
                validator: validator
            )
        }
        return try RemoteMarkdownSource(
            openedURL: openedURL,
            resolvedURL: resolvedURL,
            sourceID: sourceID,
            writeURL: writeURL,
            pollingInterval: interval,
            validator: validator
        )
    }
}
