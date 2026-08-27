import AppKit
import AvivCore

@MainActor
final class LiveDocumentLinkPopoverViewController: NSViewController {
    private let pasteboard: NSPasteboard
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Live Document")
    private let statusLabel = NSTextField(labelWithString: "")
    private let connectedLabel = NSTextField(labelWithString: "Connected to")
    private let linkContainer = NSView()
    private let linkField = NSTextField(string: "")
    private let copyButton = NSButton()
    private var copyFeedbackTask: Task<Void, Never>?
    private var presentation: RemoteSyncPresentation

    private(set) var sourceURL: URL

    var sourceURLStringForTesting: String {
        linkField.stringValue
    }

    var linkFieldIsSelectableForTesting: Bool {
        linkField.isSelectable
    }

    var elementIdentifiersForTesting: Set<String> {
        [
            view.accessibilityIdentifier(),
            linkField.accessibilityIdentifier(),
            copyButton.accessibilityIdentifier(),
        ].compactMap(\.self).reduce(into: Set<String>()) { $0.insert($1) }
    }

    init(
        sourceURL: URL,
        presentation: RemoteSyncPresentation,
        pasteboard: NSPasteboard
    ) {
        self.sourceURL = sourceURL
        self.presentation = presentation
        self.pasteboard = pasteboard
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 392, height: 108)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.setAccessibilityElement(true)
        root.setAccessibilityIdentifier("aviv.live-document-link.popover")
        root.setAccessibilityRole(.group)
        root.setAccessibilityRoleDescription("Live document link")
        root.setAccessibilityLabel("Live document link")
        root.setAccessibilityHelp(
            "Shows and copies the HTTPS address backing the current live Markdown document."
        )
        root.setAccessibilityEnabled(true)
        view = root

        configureViews()
        installViews(in: root)
        update(sourceURL: sourceURL, presentation: presentation)
    }

    func update(sourceURL: URL, presentation: RemoteSyncPresentation) {
        self.sourceURL = sourceURL
        self.presentation = presentation
        guard isViewLoaded else { return }
        copyFeedbackTask?.cancel()
        linkField.stringValue = sourceURL.absoluteString
        linkField.toolTip = sourceURL.absoluteString
        linkField.setAccessibilityValue(sourceURL.absoluteString)
        statusLabel.stringValue = statusText(for: presentation)
        statusLabel.setAccessibilityValue(statusLabel.stringValue)
        view.setAccessibilityValue(
            "\(sourceURL.absoluteString); \(presentation.detail); \(presentation.isWritable ? "writable" : "read-only")"
        )
    }

    func copyLinkForTesting() {
        copyLink(nil)
    }

    private func configureViews() {
        iconView.image = NSImage(
            systemSymbolName: "network",
            accessibilityDescription: nil
        )
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 12.5,
            weight: .semibold
        )
        iconView.contentTintColor = MarkdownTheme.clean.secondaryTextColor
        iconView.setAccessibilityElement(false)
        iconView.setAccessibilityHidden(true)

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = MarkdownTheme.clean.textColor

        statusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.textColor = MarkdownTheme.clean.secondaryTextColor
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setAccessibilityElement(true)
        statusLabel.setAccessibilityIdentifier("aviv.live-document-link.status")
        statusLabel.setAccessibilityLabel("Live document status")
        statusLabel.setAccessibilityEnabled(true)

        connectedLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        connectedLabel.textColor = MarkdownTheme.clean.secondaryTextColor.withAlphaComponent(0.82)

        linkContainer.wantsLayer = true
        linkContainer.layer?.cornerRadius = 6
        linkContainer.layer?.backgroundColor =
            NSColor.controlBackgroundColor
            .withAlphaComponent(0.72).cgColor
        linkContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        linkContainer.layer?.borderWidth = 0.5

        linkField.isEditable = false
        linkField.isSelectable = true
        linkField.isBordered = false
        linkField.drawsBackground = false
        linkField.focusRingType = .none
        linkField.usesSingleLineMode = true
        linkField.lineBreakMode = .byTruncatingMiddle
        linkField.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        linkField.textColor = MarkdownTheme.clean.textColor
        linkField.setAccessibilityElement(true)
        linkField.setAccessibilityIdentifier("aviv.live-document-link.url")
        linkField.setAccessibilityRole(.textField)
        linkField.setAccessibilityLabel("Live document URL")
        linkField.setAccessibilityHelp(
            "Selectable HTTPS address backing the current live Markdown document."
        )
        linkField.setAccessibilityEnabled(true)

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: nil
        )
        copyButton.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 11,
            weight: .medium
        )
        copyButton.target = self
        copyButton.action = #selector(copyLink(_:))
        copyButton.isBordered = false
        copyButton.bezelStyle = .toolbar
        copyButton.focusRingType = .default
        copyButton.toolTip = "Copy live document URL"
        copyButton.setAccessibilityElement(true)
        copyButton.setAccessibilityIdentifier("aviv.live-document-link.copy")
        copyButton.setAccessibilityRole(.button)
        copyButton.setAccessibilityLabel("Copy live document URL")
        copyButton.setAccessibilityHelp(
            "Copies the complete live Markdown document address to the clipboard."
        )
        copyButton.setAccessibilityEnabled(true)
    }

    private func installViews(in root: NSView) {
        for item in [iconView, titleLabel, statusLabel, connectedLabel, linkContainer] {
            item.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(item)
        }
        for item in [linkField, copyButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
            linkContainer.addSubview(item)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: root.topAnchor, constant: 13),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 12
            ),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 168),

            connectedLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            connectedLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 7),

            linkContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            linkContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            linkContainer.topAnchor.constraint(equalTo: connectedLabel.bottomAnchor, constant: 3),
            linkContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            linkContainer.heightAnchor.constraint(equalToConstant: 30),

            linkField.leadingAnchor.constraint(equalTo: linkContainer.leadingAnchor, constant: 9),
            linkField.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -5),
            linkField.centerYAnchor.constraint(equalTo: linkContainer.centerYAnchor),

            copyButton.trailingAnchor.constraint(
                equalTo: linkContainer.trailingAnchor,
                constant: -3
            ),
            copyButton.centerYAnchor.constraint(equalTo: linkContainer.centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc private func copyLink(_ sender: Any?) {
        pasteboard.clearContents()
        pasteboard.setString(sourceURL.absoluteString, forType: .string)
        let restoredStatus = statusText(for: presentation)
        statusLabel.stringValue = "Copied"
        statusLabel.setAccessibilityValue("Copied")
        NSAccessibility.post(element: statusLabel, notification: .valueChanged)
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            statusLabel.stringValue = restoredStatus
            statusLabel.setAccessibilityValue(restoredStatus)
        }
    }

    private func statusText(for presentation: RemoteSyncPresentation) -> String {
        presentation.detail.replacingOccurrences(of: "Live • ", with: "")
    }
}
