import Foundation

public struct RemoteMarkdownValidator: Equatable, Sendable {
    public let etag: String?
    public let lastModified: String?

    public init(etag: String?, lastModified: String?) {
        self.etag = etag
        self.lastModified = lastModified
    }

    public var isEmpty: Bool {
        etag == nil && lastModified == nil
    }
}

public struct RemoteMarkdownSource: Equatable, Sendable {
    public static let defaultPollingInterval: TimeInterval = 1
    public static let minimumPollingInterval: TimeInterval = 1
    public static let maximumPollingInterval: TimeInterval = 60

    public let openedURL: URL
    public let resolvedURL: URL
    public let sourceID: String
    public let writeURL: URL?
    public let pollingInterval: TimeInterval
    public let validator: RemoteMarkdownValidator

    public init(
        openedURL: URL,
        resolvedURL: URL,
        sourceID: String,
        writeURL: URL?,
        pollingInterval: TimeInterval,
        validator: RemoteMarkdownValidator
    ) throws {
        guard Self.isAllowedRemoteURL(openedURL), Self.isAllowedRemoteURL(resolvedURL) else {
            throw RemoteMarkdownError.insecureURL
        }
        if let writeURL, !Self.isAllowedRemoteURL(writeURL) {
            throw RemoteMarkdownError.insecureWriteURL
        }
        let trimmedSourceID = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceID.isEmpty, trimmedSourceID.utf8.count <= 1_024,
            trimmedSourceID.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw RemoteMarkdownError.missingSourceIdentity
        }
        guard pollingInterval.isFinite else {
            throw RemoteMarkdownError.invalidPollingInterval
        }
        if writeURL != nil {
            guard
                let etag = validator.etag?.trimmingCharacters(in: .whitespacesAndNewlines),
                !etag.isEmpty
            else {
                throw RemoteMarkdownError.missingWriteValidator
            }
        }

        self.openedURL = openedURL
        self.resolvedURL = resolvedURL
        self.sourceID = trimmedSourceID
        self.writeURL = writeURL
        self.pollingInterval = min(
            Self.maximumPollingInterval,
            max(Self.minimumPollingInterval, pollingInterval)
        )
        self.validator = validator
    }

    public var isWritable: Bool {
        writeURL != nil
    }

    public var displayHost: String {
        resolvedURL.host(percentEncoded: false) ?? resolvedURL.host ?? "Remote source"
    }

    public func updating(
        resolvedURL: URL,
        sourceID: String,
        writeURL: URL?,
        pollingInterval: TimeInterval,
        validator: RemoteMarkdownValidator
    ) throws -> RemoteMarkdownSource {
        guard sourceID == self.sourceID else {
            throw RemoteMarkdownError.sourceIdentityChanged
        }
        return try RemoteMarkdownSource(
            openedURL: openedURL,
            resolvedURL: resolvedURL,
            sourceID: sourceID,
            writeURL: writeURL,
            pollingInterval: pollingInterval,
            validator: validator
        )
    }

    public static func isAllowedRemoteURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host != nil else { return false }
        return url.user == nil && url.password == nil
    }
}

public struct RemoteMarkdownSnapshot: Equatable, Sendable {
    public let markdown: String
    public let source: RemoteMarkdownSource

    public init(markdown: String, source: RemoteMarkdownSource) {
        self.markdown = markdown
        self.source = source
    }
}

public enum RemoteMarkdownError: Error, Equatable, LocalizedError, Sendable {
    case insecureURL
    case insecureWriteURL
    case invalidResponse
    case unexpectedStatus(Int)
    case invalidMarkdownEncoding
    case documentTooLarge
    case missingSourceIdentity
    case invalidPollingInterval
    case sourceIdentityChanged
    case readOnly
    case missingCredential
    case missingWriteValidator
    case incomingConflict
    case writeConflict

    public var errorDescription: String? {
        switch self {
        case .insecureURL:
            return
                "Aviv opens remote Markdown only from public HTTPS URLs without embedded credentials."
        case .insecureWriteURL:
            return
                "The source advertised an unsafe write endpoint. Aviv did not send document data."
        case .invalidResponse:
            return "The remote Markdown server returned an invalid response."
        case .unexpectedStatus(let status):
            return "The remote Markdown server returned HTTP \(status)."
        case .invalidMarkdownEncoding:
            return "The downloaded document is not valid UTF-8 or UTF-16 Markdown text."
        case .documentTooLarge:
            return "The remote Markdown document exceeds Aviv's 16 MiB safety limit."
        case .missingSourceIdentity:
            return "The remote document has no stable source identity."
        case .invalidPollingInterval:
            return "The remote source advertised an invalid polling interval."
        case .sourceIdentityChanged:
            return "The server changed this document's source identity while it was open."
        case .readOnly:
            return
                "This URL is read-only because its server did not advertise an authenticated Aviv write bridge."
        case .missingCredential:
            return "Saving this URL requires its remote write credential."
        case .missingWriteValidator:
            return "The remote source did not provide an ETag required for conflict-safe saving."
        case .incomingConflict:
            return "Incoming edits are waiting. Resolve them before saving."
        case .writeConflict:
            return
                "The remote document changed before this save completed. Your local edits were preserved."
        }
    }
}
