import AppKit

final class RemoteEdgePulseView: NSView {
    private var fadeWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = MarkdownTheme.clean.accentColor.withAlphaComponent(0.58).cgColor
        alphaValue = 0
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func pulse(color: NSColor) {
        fadeWorkItem?.cancel()
        layer?.backgroundColor = color.withAlphaComponent(0.58).cgColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.78
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self?.animator().alphaValue = 0
            }
        }
        fadeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }
}

final class RemoteChangedLineMarkerView: NSView {
    weak var textView: MarkdownTextView?
    var lineRanges: [NSRange] = [] {
        didSet {
            needsDisplay = true
            setAccessibilityElement(!lineRanges.isEmpty)
            setAccessibilityValue(
                lineRanges.isEmpty
                    ? "No externally changed lines"
                    : "\(lineRanges.count) externally changed line regions"
            )
            setAccessibilityHidden(lineRanges.isEmpty)
        }
    }

    init(textView: MarkdownTextView) {
        self.textView = textView
        super.init(frame: .zero)
        setAccessibilityElement(false)
        setAccessibilityIdentifier("remote-changed-lines")
        setAccessibilityLabel("Externally changed lines")
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription("Remote document change markers")
        setAccessibilityHelp(
            "Marks document lines most recently changed by the remote source."
        )
        setAccessibilityEnabled(true)
        setAccessibilityValue("No externally changed lines")
        setAccessibilityHidden(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }
        let color = textView.styler.theme.accentColor.withAlphaComponent(0.72)
        color.setFill()
        for range in lineRanges.prefix(200) {
            let safeRange = NSIntersectionRange(
                range,
                NSRange(location: 0, length: (textView.string as NSString).length)
            )
            guard safeRange.length > 0 else { continue }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: safeRange,
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            rect = convert(rect, from: textView)
            let marker = NSRect(
                x: max(4, rect.minX - 10),
                y: rect.minY + 2,
                width: 3,
                height: max(8, rect.height - 4)
            )
            NSBezierPath(roundedRect: marker, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

final class RemoteSyncToastView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.86).cgColor
        layer?.cornerRadius = 12
        alphaValue = 0
        isHidden = true
        setAccessibilityElement(false)
        setAccessibilityIdentifier("remote-sync-toast")
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription("Remote synchronization alert")
        setAccessibilityLabel("Remote synchronization status")
        setAccessibilityEnabled(true)
        setAccessibilityHelp("Transient status for remote document changes and conflicts.")
        setAccessibilityHidden(true)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = .white
        iconView.setAccessibilityElement(false)
        iconView.setAccessibilityHidden(true)
        iconView.cell?.setAccessibilityElement(false)
        iconView.cell?.setAccessibilityHidden(true)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(true)
        label.setAccessibilityIdentifier("remote-sync-toast-message")
        label.setAccessibilityRole(.staticText)
        label.setAccessibilityRoleDescription("Remote synchronization message")
        label.setAccessibilityLabel("Remote sync message")
        label.setAccessibilityEnabled(true)
        label.setAccessibilityHelp(
            "Visible message describing the latest remote synchronization event."
        )
        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(message: String, conflict: Bool = false) {
        hideWorkItem?.cancel()
        label.stringValue = message
        label.setAccessibilityValue(message)
        isHidden = false
        setAccessibilityElement(true)
        setAccessibilityHidden(false)
        setAccessibilityValue(message)
        setAccessibilityHelp(
            conflict
                ? "Remote synchronization conflict. \(message). Open the conflict controls to choose which document version to keep."
                : "Remote synchronization update. \(message)."
        )
        layer?.backgroundColor =
            conflict
            ? NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.13, alpha: 0.91).cgColor
            : NSColor(calibratedWhite: 0.12, alpha: 0.86).cgColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
        guard !conflict else { return }
        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.36
                self?.animator().alphaValue = 0
            }
            self?.setAccessibilityElement(false)
            self?.setAccessibilityHidden(true)
            self?.isHidden = true
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: workItem)
    }

    func dismiss() {
        hideWorkItem?.cancel()
        alphaValue = 0
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
        isHidden = true
    }
}
