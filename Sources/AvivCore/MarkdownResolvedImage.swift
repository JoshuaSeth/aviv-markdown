import AppKit

public struct MarkdownResolvedImage {
    public let image: NSImage?
    public let displayName: String
    public let sourceURL: URL?

    public init(image: NSImage?, displayName: String, sourceURL: URL?) {
        self.image = image
        self.displayName = displayName
        self.sourceURL = sourceURL
    }
}
