import AppKit

public struct MarkdownTheme {
    public let backgroundColor: NSColor
    public let editorBackgroundColor: NSColor
    public let textColor: NSColor
    public let secondaryTextColor: NSColor
    public let syntaxVisibleColor: NSColor
    public let syntaxHiddenColor: NSColor
    public let accentColor: NSColor
    public let codeBackgroundColor: NSColor
    public let quoteBarColor: NSColor
    public let selectionColor: NSColor
    public let viewScale: CGFloat

    public static let defaultViewScale: CGFloat = 0.86
    public static let minimumViewScale: CGFloat = 0.60
    public static let maximumViewScale: CGFloat = 1.60
    public static let zoomStep: CGFloat = 1.10

    public static let clean = MarkdownTheme(
        backgroundColor: NSColor(calibratedRed: 0.985, green: 0.986, blue: 0.982, alpha: 1.0),
        editorBackgroundColor: NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.995, alpha: 1.0),
        textColor: NSColor(calibratedRed: 0.105, green: 0.111, blue: 0.125, alpha: 1.0),
        secondaryTextColor: NSColor(calibratedRed: 0.420, green: 0.444, blue: 0.488, alpha: 1.0),
        syntaxVisibleColor: NSColor(calibratedRed: 0.540, green: 0.565, blue: 0.615, alpha: 1.0),
        syntaxHiddenColor: NSColor(calibratedWhite: 0.0, alpha: 0.0),
        accentColor: NSColor(calibratedRed: 0.055, green: 0.390, blue: 0.680, alpha: 1.0),
        codeBackgroundColor: NSColor(calibratedRed: 0.940, green: 0.946, blue: 0.952, alpha: 1.0),
        quoteBarColor: NSColor(calibratedRed: 0.125, green: 0.510, blue: 0.455, alpha: 1.0),
        selectionColor: NSColor(calibratedRed: 0.735, green: 0.855, blue: 0.965, alpha: 0.55),
        viewScale: defaultViewScale
    )

    public init(
        backgroundColor: NSColor,
        editorBackgroundColor: NSColor,
        textColor: NSColor,
        secondaryTextColor: NSColor,
        syntaxVisibleColor: NSColor,
        syntaxHiddenColor: NSColor,
        accentColor: NSColor,
        codeBackgroundColor: NSColor,
        quoteBarColor: NSColor,
        selectionColor: NSColor,
        viewScale: CGFloat = MarkdownTheme.defaultViewScale
    ) {
        self.backgroundColor = backgroundColor
        self.editorBackgroundColor = editorBackgroundColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.syntaxVisibleColor = syntaxVisibleColor
        self.syntaxHiddenColor = syntaxHiddenColor
        self.accentColor = accentColor
        self.codeBackgroundColor = codeBackgroundColor
        self.quoteBarColor = quoteBarColor
        self.selectionColor = selectionColor
        self.viewScale = Self.clampedViewScale(viewScale)
    }

    public var fontScale: CGFloat {
        viewScale
    }

    public var bodyFont: NSFont {
        NSFont.systemFont(ofSize: scaled(17), weight: .regular)
    }

    public var boldFont: NSFont {
        NSFont.systemFont(ofSize: scaled(17), weight: .semibold)
    }

    public var codeFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: scaled(15), weight: .regular)
    }

    public var smallFont: NSFont {
        NSFont.systemFont(ofSize: scaled(12.5), weight: .medium)
    }

    public func headingFont(level: Int) -> NSFont {
        switch max(1, min(level, 6)) {
        case 1:
            return NSFont.systemFont(ofSize: scaled(34), weight: .bold)
        case 2:
            return NSFont.systemFont(ofSize: scaled(27), weight: .bold)
        case 3:
            return NSFont.systemFont(ofSize: scaled(22), weight: .semibold)
        case 4:
            return NSFont.systemFont(ofSize: scaled(19), weight: .semibold)
        case 5:
            return NSFont.systemFont(ofSize: scaled(17), weight: .semibold)
        default:
            return NSFont.systemFont(ofSize: scaled(16), weight: .semibold)
        }
    }

    public func withFontScale(_ scale: CGFloat) -> MarkdownTheme {
        withViewScale(scale)
    }

    public func withViewScale(_ scale: CGFloat) -> MarkdownTheme {
        MarkdownTheme(
            backgroundColor: backgroundColor,
            editorBackgroundColor: editorBackgroundColor,
            textColor: textColor,
            secondaryTextColor: secondaryTextColor,
            syntaxVisibleColor: syntaxVisibleColor,
            syntaxHiddenColor: syntaxHiddenColor,
            accentColor: accentColor,
            codeBackgroundColor: codeBackgroundColor,
            quoteBarColor: quoteBarColor,
            selectionColor: selectionColor,
            viewScale: scale
        )
    }

    public func zoomedIn() -> MarkdownTheme {
        withViewScale(viewScale * Self.zoomStep)
    }

    public func zoomedOut() -> MarkdownTheme {
        withViewScale(viewScale / Self.zoomStep)
    }

    public func paragraphStyle(
        lineSpacing: CGFloat = 5,
        paragraphSpacing: CGFloat = 12,
        paragraphSpacingBefore: CGFloat = 0,
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = scaledSpacing(lineSpacing)
        style.paragraphSpacing = scaledSpacing(paragraphSpacing)
        style.paragraphSpacingBefore = scaledSpacing(paragraphSpacingBefore)
        style.firstLineHeadIndent = scaledMetric(firstLineHeadIndent)
        style.headIndent = scaledMetric(headIndent)
        style.lineBreakMode = .byWordWrapping
        return style.copy() as! NSParagraphStyle
    }

    public var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle(),
            .kern: 0,
            .ligature: 1
        ]
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        max(1, value * viewScale)
    }

    public func scaledMetric(_ value: CGFloat, minimum: CGFloat = 0) -> CGFloat {
        max(minimum, value * viewScale)
    }

    public func scaledSpacing(_ value: CGFloat) -> CGFloat {
        max(0, value * viewScale)
    }

    private static func clampedViewScale(_ scale: CGFloat) -> CGFloat {
        min(maximumViewScale, max(minimumViewScale, scale))
    }
}
