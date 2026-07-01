import AppKit
import Foundation

public enum MarkdownDocumentFormat: String, CaseIterable {
    case blog
    case a4

    public static let defaultsKey = "Aviv.DocumentFormat"

    public static func stored(in defaults: UserDefaults = .standard) -> MarkdownDocumentFormat {
        guard
            let rawValue = defaults.string(forKey: defaultsKey),
            let format = MarkdownDocumentFormat(rawValue: rawValue)
        else {
            return .blog
        }
        return format
    }

    public var displayName: String {
        switch self {
        case .blog:
            return "Blog"
        case .a4:
            return "A4"
        }
    }

    public var menuTitle: String {
        switch self {
        case .blog:
            return "Blog format"
        case .a4:
            return "A4 document"
        }
    }

    public var editorContentWidth: CGFloat {
        switch self {
        case .blog:
            return 820
        case .a4:
            return 930
        }
    }

    public func editorHorizontalPadding(scale: CGFloat) -> CGFloat {
        switch self {
        case .blog:
            return max(20, 28 * scale)
        case .a4:
            return max(18, 22 * scale)
        }
    }

    public func editorVerticalInset(scale: CGFloat) -> CGFloat {
        switch self {
        case .blog:
            return max(48, 76 * scale)
        case .a4:
            return max(44, 62 * scale)
        }
    }

    public var paperSize: NSSize {
        switch self {
        case .blog:
            return NSSize(width: 595.28, height: 841.89)
        case .a4:
            return NSSize(width: 595.28, height: 841.89)
        }
    }

    public var printMargins: NSEdgeInsets {
        switch self {
        case .blog:
            return NSEdgeInsets(top: 42, left: 42, bottom: 42, right: 42)
        case .a4:
            return NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        }
    }

    public var printViewScale: CGFloat {
        switch self {
        case .blog:
            return 0.92
        case .a4:
            return 0.94
        }
    }

    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
