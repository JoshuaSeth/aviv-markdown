import Foundation

public enum MarkdownDocumentIO {
    public static func read(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        throw CocoaError(.fileReadUnknownStringEncoding)
    }

    public static func write(_ markdown: String, to url: URL) throws {
        try markdown.data(using: .utf8)?.write(to: url, options: [.atomic])
    }
}
