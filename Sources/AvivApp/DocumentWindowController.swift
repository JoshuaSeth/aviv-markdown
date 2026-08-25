import AppKit
import AvivCore
import UniformTypeIdentifiers

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let workspace = EditorWorkspaceView()
    var onRequestNewDocument: ((Any?) -> Void)?
    var onWindowWillClose: ((DocumentWindowController) -> Void)?
    var onDocumentURLAccessed: ((URL) -> Void)?

    var remoteIndicatorIdentifiersForTesting: [String] {
        RemoteSyncIndicatorView.indicatorIdentifiers
            + workspace.remoteIndicatorIdentifiersForTesting
    }

    var liveDocumentIndicatorFrameForTesting: NSRect? {
        guard window?.toolbar?.items.contains(where: { $0.itemIdentifier == .liveDocument }) == true
        else { return nil }
        return workspace.convert(remoteSyncToolbarView.bounds, from: remoteSyncToolbarView)
    }

    var liveDocumentIndicatorVisibleTextForTesting: String {
        remoteSyncToolbarView.visibleTextForTesting
    }

    var liveDocumentIndicatorAccessibilitySummaryForTesting: String {
        remoteSyncToolbarView.accessibilitySummaryForTesting
    }

    var documentTitleFrameForTesting: NSRect {
        let visibleTitleView = documentTitleToolbarView.visibleTitleView
        return workspace.convert(visibleTitleView.bounds, from: visibleTitleView)
    }

    var documentTitleTextForTesting: String {
        documentTitleToolbarView.stringValue
    }

    var canRevertToSaved: Bool {
        isEdited || documentURL != nil
    }

    var representedDocumentURL: URL? {
        documentURL
    }

    var representedRemoteSource: RemoteMarkdownSource? {
        remoteSource
    }

    var canReuseForOpenedDocument: Bool {
        documentURL == nil && !isEdited
            && (workspace.textView.string.isEmpty
                || workspace.textView.string == MarkdownSamples.starter)
    }

    private let printService: DocumentPrintService
    private let remoteSyncToolbarView = RemoteSyncIndicatorView(
        frame: NSRect(x: 0, y: 0, width: 28, height: 28)
    )
    private let documentTitleToolbarView = DocumentTitleToolbarView()
    let remoteTransport: any RemoteMarkdownTransport
    let remoteCredentialStore: any RemoteWriteCredentialStoring
    var documentURL: URL?
    var savedText = MarkdownSamples.starter
    var remoteSyncController: RemoteDocumentSyncController?
    var remoteOpeningController: RemoteDocumentSyncController?
    var remoteSource: RemoteMarkdownSource?
    var remoteOpenGeneration: UInt64 = 0
    var lastExternalUpdateResult: ExternalMarkdownUpdateResult?
    var hasPendingRemoteConflict = false
    var isEdited = false {
        didSet {
            window?.isDocumentEdited = isEdited
            workspace.updateDocumentTitle(url: documentURL, isEdited: isEdited)
            updateWindowTitle()
        }
    }

    init(
        printService: DocumentPrintService? = nil,
        remoteTransport: any RemoteMarkdownTransport = URLSessionRemoteMarkdownTransport(),
        remoteCredentialStore: any RemoteWriteCredentialStoring =
            KeychainRemoteWriteCredentialStore()
    ) {
        self.printService = printService ?? AppKitDocumentPrintService()
        self.remoteTransport = remoteTransport
        self.remoteCredentialStore = remoteCredentialStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Aviv"
        window.setAccessibilityIdentifier("aviv.document.window")
        window.setAccessibilityLabel("Aviv Markdown document window")
        window.setAccessibilityEnabled(true)
        window.setAccessibilityHelp(
            "Document window containing Aviv's Markdown editor, document outline, toolbar, title, statistics, and synchronization status."
        )
        // Keep the document title available to AppKit for tabs, Window menu entries,
        // accessibility, and represented-document behavior. Aviv presents one subtle
        // title through AppKit's centered toolbar slot, so the native title must not be
        // painted a second time on top of it.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 520)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.documentTabbingIdentifier
        window.center()

        super.init(window: window)

        window.delegate = self
        workspace.showsDocumentTitle = false
        window.contentView = workspace
        configureToolbar()
        workspace.onRemoteSyncPresentationChange = { [weak self] presentation in
            self?.updateLiveDocumentToolbar(presentation)
        }
        workspace.setDocumentURL(nil)
        workspace.loadMarkdown(MarkdownSamples.starter)
        workspace.updateDocumentTitle(url: nil, isEdited: false)
        updateWindowTitle()
        DispatchQueue.main.async { [weak self] in
            self?.alignDocumentTitleForCurrentLayout()
        }
        workspace.textView.onContentChange = { [weak self] text in
            guard let self else { return }
            self.isEdited = text != self.savedText
            self.workspace.scheduleMetricsUpdate()
        }
        workspace.textView.onSelectionChange = { [weak self] in
            self?.workspace.scheduleMetricsUpdate()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func newDocument(_ sender: Any?) {
        if let onRequestNewDocument {
            onRequestNewDocument(sender)
            return
        }

        resetToEmptyDocument()
    }

    func resetToEmptyDocument() {
        if confirmDiscardIfNeeded() {
            stopRemoteSync()
            documentURL = nil
            savedText = ""
            workspace.setDocumentURL(nil)
            workspace.loadMarkdown("")
            isEdited = false
            window?.representedURL = nil
            updateWindowTitle()
            workspace.textView.window?.makeFirstResponder(workspace.textView)
        }
    }

    @objc func openDocument(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url: url)
        }
    }

    @discardableResult
    func open(url: URL) -> Bool {
        if !url.isFileURL {
            Task { [weak self] in
                _ = await self?.openRemote(url: url)
            }
            return true
        }
        do {
            let text = try MarkdownDocumentIO.read(from: url)
            stopRemoteSync()
            documentURL = url
            savedText = text
            workspace.setDocumentURL(url)
            workspace.loadMarkdown(text)
            isEdited = false
            window?.representedURL = url
            updateWindowTitle()
            workspace.textView.window?.makeFirstResponder(workspace.textView)
            onDocumentURLAccessed?(url)
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        if remoteSyncController?.isActive == true {
            Task { [weak self] in
                await self?.saveRemoteDocument()
            }
            return
        }
        if let documentURL {
            save(to: documentURL)
        } else {
            saveDocumentAs(sender)
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.markdownContentTypes
        panel.nameFieldStringValue = documentURL?.lastPathComponent ?? "Untitled.md"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.save(to: url)
        }
    }

    private func save(to url: URL) {
        do {
            let text = workspace.textView.string
            try MarkdownDocumentIO.write(text, to: url)
            stopRemoteSync()
            documentURL = url
            savedText = text
            workspace.setDocumentURL(url)
            window?.representedURL = url
            isEdited = false
            updateWindowTitle()
            onDocumentURLAccessed?(url)
        } catch {
            presentError(error)
        }
    }

    @objc func closeDocument(_ sender: Any?) {
        window?.performClose(sender)
    }

    @objc func revertDocumentToSaved(_ sender: Any?) {
        guard confirmRevertIfNeeded() else { return }

        if remoteSyncController?.isActive == true {
            Task { [weak self] in
                await self?.pollRemoteNow()
            }
            return
        }
        if let documentURL {
            open(url: documentURL)
        } else {
            workspace.loadMarkdown(savedText)
            isEdited = false
            workspace.textView.window?.makeFirstResponder(workspace.textView)
        }
    }

    @objc func pageSetup(_ sender: Any?) {
        printService.runPageSetup(window: window)
    }

    @objc func printDocument(_ sender: Any?) {
        let title = documentURL?.lastPathComponent ?? "Untitled"
        printService.print(
            markdown: workspace.textView.string,
            title: title,
            format: workspace.documentFormat,
            baseURL: documentURL?.deletingLastPathComponent(),
            window: window
        )
    }

    @objc func increaseTextSize(_ sender: Any?) {
        workspace.textView.increaseTextSize()
    }

    @objc func decreaseTextSize(_ sender: Any?) {
        workspace.textView.decreaseTextSize()
    }

    @objc func resetTextSize(_ sender: Any?) {
        workspace.textView.resetTextSize()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmDiscardIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        stopRemoteSync()
        onWindowWillClose?(self)
    }

    func windowDidResize(_ notification: Notification) {
        alignDocumentTitleForCurrentLayout()
    }

    func confirmDiscardIfNeeded() -> Bool {
        guard isEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes?"
        alert.informativeText = "This document has unsaved changes."
        let saveButton = alert.addButton(withTitle: "Save")
        saveButton.setAccessibilityIdentifier("aviv.unsaved-changes.save")
        saveButton.setAccessibilityHelp("Saves the current Markdown document before continuing.")
        let discardButton = alert.addButton(withTitle: "Discard")
        discardButton.setAccessibilityIdentifier("aviv.unsaved-changes.discard")
        discardButton.setAccessibilityHelp("Discards unsaved Markdown changes and continues.")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.setAccessibilityIdentifier("aviv.unsaved-changes.cancel")
        cancelButton.setAccessibilityHelp("Keeps the document open with its unsaved changes.")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            saveDocument(nil)
            return !isEdited
        }
        return response == .alertSecondButtonReturn
    }

    private func confirmRevertIfNeeded() -> Bool {
        guard isEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Revert changes?"
        alert.informativeText = "This will discard edits and reload the last saved document state."
        let revertButton = alert.addButton(withTitle: "Revert")
        revertButton.setAccessibilityIdentifier("aviv.revert.confirm")
        revertButton.setAccessibilityHelp("Discards local edits and reloads the saved document.")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.setAccessibilityIdentifier("aviv.revert.cancel")
        cancelButton.setAccessibilityHelp("Returns to the document without reverting changes.")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func updateWindowTitle() {
        let base = documentURL?.lastPathComponent ?? "Untitled"
        window?.title = base
        documentTitleToolbarView.update(title: isEdited ? "\(base) *" : base)
    }

    func alignDocumentTitleForCurrentLayout() {
        guard documentTitleToolbarView.window != nil else { return }
        documentTitleToolbarView.setTitleWidth(maximumCenteredTitleWidth())
        documentTitleToolbarView.layoutSubtreeIfNeeded()
        let itemFrame = workspace.convert(
            documentTitleToolbarView.bounds,
            from: documentTitleToolbarView
        )
        documentTitleToolbarView.setHorizontalOffset(
            workspace.bounds.midX - itemFrame.midX
        )
        documentTitleToolbarView.layoutSubtreeIfNeeded()
    }

    private func maximumCenteredTitleWidth() -> CGFloat {
        let fullTitleWidth: CGFloat = 184
        let minimumTitleWidth: CGFloat = 112
        let controlClearance: CGFloat = 8
        guard let frameView = window?.contentView?.superview else { return fullTitleWidth }

        let centerX = workspace.bounds.midX
        let toolbarBand = NSRect(
            x: workspace.bounds.minX,
            y: workspace.bounds.maxY - 54,
            width: workspace.bounds.width,
            height: 54
        )
        var leftBoundary = workspace.bounds.minX
        var rightBoundary = workspace.bounds.maxX

        func measureButtons(in view: NSView) {
            if view is NSButton, !view.isHidden, view.alphaValue > 0 {
                let frame = workspace.convert(view.bounds, from: view)
                if frame.intersects(toolbarBand) {
                    if frame.maxX <= centerX {
                        leftBoundary = max(leftBoundary, frame.maxX)
                    } else if frame.minX >= centerX {
                        rightBoundary = min(rightBoundary, frame.minX)
                    }
                }
            }
            view.subviews.forEach { measureButtons(in: $0) }
        }
        measureButtons(in: frameView)

        let availableHalfWidth = max(
            0,
            min(centerX - leftBoundary, rightBoundary - centerX) - controlClearance
        )
        return min(
            fullTitleWidth,
            max(minimumTitleWidth, floor(availableHalfWidth * 2))
        )
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "Aviv.Toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifier = .documentTitle
        window?.toolbar = toolbar
    }

    private func updateLiveDocumentToolbar(_ presentation: RemoteSyncPresentation?) {
        guard let toolbar = window?.toolbar else { return }
        guard let presentation else {
            if let saveButton = toolbar.items.first(where: {
                $0.itemIdentifier == .saveDocument
            })?.view as? AccessibleToolbarButton {
                saveButton.setAccessibilityValue("Local document save is available")
                saveButton.setAccessibilityHelp(
                    "Saves the current Markdown document to its local file."
                )
            }
            if let index = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == .liveDocument
            }) {
                toolbar.removeItem(at: index)
            }
            return
        }

        remoteSyncToolbarView.update(presentation, theme: .clean)
        if !toolbar.items.contains(where: { $0.itemIdentifier == .liveDocument }) {
            toolbar.insertItem(
                withItemIdentifier: .liveDocument,
                at: min(3, toolbar.items.count)
            )
        }
        toolbar.items.first(where: { $0.itemIdentifier == .liveDocument })?.toolTip =
            remoteSyncToolbarView.accessibilitySummaryForTesting
        if let saveButton = toolbar.items.first(where: {
            $0.itemIdentifier == .saveDocument
        })?.view as? AccessibleToolbarButton {
            saveButton.setAccessibilityValue(
                presentation.isWritable
                    ? "Live document save is available"
                    : "Live document source is read-only"
            )
            saveButton.setAccessibilityHelp(
                presentation.isWritable
                    ? "Saves this live Markdown document securely to its remote source."
                    : "This live Markdown source is read-only, so remote save is unavailable."
            )
        }
        window?.contentView?.superview?.layoutSubtreeIfNeeded()
        alignDocumentTitleForCurrentLayout()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .newDocument, .openDocument, .saveDocument, .liveDocument, .flexibleSpace,
            .documentTitle, .flexibleSpace, .zoomOut, .actualSize, .zoomIn, .bold, .italic, .code,
            .heading1, .heading2,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .newDocument, .openDocument, .saveDocument, .flexibleSpace, .documentTitle,
            .flexibleSpace, .zoomOut, .actualSize, .zoomIn, .bold, .italic, .code, .heading1,
            .heading2,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self

        switch itemIdentifier {
        case .newDocument:
            configureToolbarAction(
                item,
                image: NSImage(systemSymbolName: "doc", accessibilityDescription: "New"),
                label: "New",
                identifier: "aviv.toolbar.new-document",
                help: "Creates a new untitled Markdown document.",
                action: #selector(newDocument(_:))
            )
        case .openDocument:
            configureToolbarAction(
                item,
                image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Open"),
                label: "Open",
                identifier: "aviv.toolbar.open-document",
                help: "Opens a local Markdown file. Use the File menu to open a live document URL.",
                action: #selector(openDocument(_:))
            )
        case .saveDocument:
            configureToolbarAction(
                item,
                image: NSImage(
                    systemSymbolName: "square.and.arrow.down",
                    accessibilityDescription: "Save"
                ),
                label: "Save",
                identifier: "aviv.toolbar.save-document",
                help: "Saves the current Markdown document to its local or writable live source.",
                action: #selector(saveDocument(_:))
            )
        case .liveDocument:
            item.view = remoteSyncToolbarView
            item.label = "Live Document"
            item.paletteLabel = "Live Document"
            item.toolTip = remoteSyncToolbarView.accessibilitySummaryForTesting
        case .documentTitle:
            item.view = documentTitleToolbarView
            item.label = "Document Title"
            item.paletteLabel = "Document Title"
            item.visibilityPriority = .high
        case .zoomOut:
            configureToolbarAction(
                item,
                image: toolbarImage(
                    named: "minus.magnifyingglass",
                    fallback: "textformat.size.smaller",
                    description: "Zoom Out"
                ),
                label: "Zoom Out",
                identifier: "aviv.toolbar.zoom-out",
                help: "Decreases the document editor text size.",
                action: #selector(decreaseTextSize(_:))
            )
        case .actualSize:
            configureToolbarAction(
                item,
                image: toolbarImage(
                    named: "1.magnifyingglass",
                    fallback: "text.magnifyingglass",
                    description: "Actual Size"
                ),
                label: "Actual Size",
                identifier: "aviv.toolbar.actual-size",
                help: "Restores the document editor's default text size.",
                action: #selector(resetTextSize(_:))
            )
        case .zoomIn:
            configureToolbarAction(
                item,
                image: toolbarImage(
                    named: "plus.magnifyingglass",
                    fallback: "textformat.size.larger",
                    description: "Zoom In"
                ),
                label: "Zoom In",
                identifier: "aviv.toolbar.zoom-in",
                help: "Increases the document editor text size.",
                action: #selector(increaseTextSize(_:))
            )
        case .bold:
            configureToolbarAction(
                item,
                image: NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold"),
                label: "Bold",
                identifier: "aviv.toolbar.bold",
                help: "Wraps the current selection in Markdown bold markers.",
                action: #selector(toggleBold(_:))
            )
        case .italic:
            configureToolbarAction(
                item,
                image: NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic"),
                label: "Italic",
                identifier: "aviv.toolbar.italic",
                help: "Wraps the current selection in Markdown italic markers.",
                action: #selector(toggleItalic(_:))
            )
        case .code:
            configureToolbarAction(
                item,
                image: NSImage(
                    systemSymbolName: "chevron.left.forwardslash.chevron.right",
                    accessibilityDescription: "Code"
                ),
                label: "Code",
                identifier: "aviv.toolbar.inline-code",
                help: "Wraps the current selection in Markdown inline-code markers.",
                action: #selector(toggleCode(_:))
            )
        case .heading1:
            configureToolbarAction(
                item,
                image: NSImage(
                    systemSymbolName: "h.square",
                    accessibilityDescription: "Heading 1"
                ),
                label: "Heading 1",
                identifier: "aviv.toolbar.heading-1",
                help: "Formats the current source line as a level 1 Markdown heading.",
                action: #selector(heading1(_:))
            )
        case .heading2:
            configureToolbarAction(
                item,
                image: NSImage(
                    systemSymbolName: "textformat.size",
                    accessibilityDescription: "Heading 2"
                ),
                label: "Heading 2",
                identifier: "aviv.toolbar.heading-2",
                help: "Formats the current source line as a level 2 Markdown heading.",
                action: #selector(heading2(_:))
            )
        default:
            return nil
        }

        if item.toolTip == nil {
            item.toolTip = item.label
        }
        return item
    }

    private func configureToolbarAction(
        _ item: NSToolbarItem,
        image: NSImage?,
        label: String,
        identifier: String,
        help: String,
        action: Selector
    ) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = help
        item.view = AccessibleToolbarButton(
            image: image,
            label: label,
            identifier: identifier,
            help: help,
            target: self,
            action: action
        )
    }

    private func toolbarImage(named name: String, fallback: String, description: String) -> NSImage?
    {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: description)
    }

    @objc private func toggleBold(_ sender: Any?) {
        workspace.textView.wrapSelection(prefix: "**", suffix: "**")
    }

    @objc private func toggleItalic(_ sender: Any?) {
        workspace.textView.wrapSelection(prefix: "_", suffix: "_")
    }

    @objc private func toggleCode(_ sender: Any?) {
        workspace.textView.wrapSelection(prefix: "`", suffix: "`")
    }

    @objc private func heading1(_ sender: Any?) {
        workspace.textView.makeHeading(level: 1)
    }

    @objc private func heading2(_ sender: Any?) {
        workspace.textView.makeHeading(level: 2)
    }
}

private final class DocumentTitleToolbarView: NSView {
    private let label = NSTextField(labelWithString: "Untitled")
    private var titleCenterConstraint: NSLayoutConstraint?
    private var titleWidthConstraint: NSLayoutConstraint?

    var visibleTitleView: NSView {
        label
    }

    var stringValue: String {
        label.stringValue
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 24)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = MarkdownTheme.clean.smallFont
        label.textColor = MarkdownTheme.clean.secondaryTextColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.setAccessibilityElement(true)
        label.setAccessibilityIdentifier("document-title-visible-text")
        label.setAccessibilityRole(.staticText)
        label.setAccessibilityRoleDescription("Visible Markdown document title")
        label.setAccessibilityLabel("Visible document title")
        label.setAccessibilityEnabled(true)
        label.setAccessibilityHelp("Visible title of the current Markdown document.")
        addSubview(label)
        let centerConstraint = label.centerXAnchor.constraint(equalTo: centerXAnchor)
        let widthConstraint = label.widthAnchor.constraint(equalToConstant: 184)
        titleCenterConstraint = centerConstraint
        titleWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            centerConstraint,
            widthConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityIdentifier("document-title")
        setAccessibilityRole(.staticText)
        setAccessibilityRoleDescription("Markdown document title")
        setAccessibilityLabel("Document title")
        setAccessibilityEnabled(true)
        setAccessibilityHelp("Title and unsaved-edit state of the current Markdown document.")
        update(title: "Untitled")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String) {
        label.stringValue = title
        label.setAccessibilityValue(title)
        setAccessibilityValue(title)
        setAccessibilityHelp(
            title.hasSuffix(" *")
                ? "Document title. The trailing asterisk means this document has unsaved changes."
                : "Document title. This document has no unsaved changes."
        )
    }

    func setHorizontalOffset(_ offset: CGFloat) {
        titleCenterConstraint?.constant = offset
    }

    func setTitleWidth(_ width: CGFloat) {
        titleWidthConstraint?.constant = width
    }
}

private final class AccessibleToolbarButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 28)
    }

    init(
        image: NSImage?,
        label: String,
        identifier: String,
        help: String,
        target: AnyObject,
        action: Selector
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        self.image = image
        self.target = target
        self.action = action
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        bezelStyle = .toolbar
        isBordered = false
        setButtonType(.momentaryPushIn)
        toolTip = help
        setAccessibilityElement(true)
        setAccessibilityIdentifier(identifier)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityHelp(help)
        setAccessibilityEnabled(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension NSToolbarItem.Identifier {
    fileprivate static let newDocument = NSToolbarItem.Identifier("Aviv.Toolbar.New")
    fileprivate static let openDocument = NSToolbarItem.Identifier("Aviv.Toolbar.Open")
    fileprivate static let saveDocument = NSToolbarItem.Identifier("Aviv.Toolbar.Save")
    fileprivate static let liveDocument = NSToolbarItem.Identifier("Aviv.Toolbar.LiveDocument")
    fileprivate static let documentTitle = NSToolbarItem.Identifier("Aviv.Toolbar.DocumentTitle")
    fileprivate static let zoomOut = NSToolbarItem.Identifier("Aviv.Toolbar.ZoomOut")
    fileprivate static let actualSize = NSToolbarItem.Identifier("Aviv.Toolbar.ActualSize")
    fileprivate static let zoomIn = NSToolbarItem.Identifier("Aviv.Toolbar.ZoomIn")
    fileprivate static let bold = NSToolbarItem.Identifier("Aviv.Toolbar.Bold")
    fileprivate static let italic = NSToolbarItem.Identifier("Aviv.Toolbar.Italic")
    fileprivate static let code = NSToolbarItem.Identifier("Aviv.Toolbar.Code")
    fileprivate static let heading1 = NSToolbarItem.Identifier("Aviv.Toolbar.Heading1")
    fileprivate static let heading2 = NSToolbarItem.Identifier("Aviv.Toolbar.Heading2")
}

extension DocumentWindowController {
    static let documentTabbingIdentifier = "Aviv.DocumentTabs"

    static var markdownContentTypes: [UTType] {
        let markdownExtensions = [
            "md",
            "markdown",
            "mdown",
            "mdwn",
            "mkd",
            "mkdn",
            "mdtxt",
            "mdtext",
            "mmd",
            "rmd",
            "rmarkdown",
            "qmd",
        ]
        var types = markdownExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(.plainText)
        return types
    }
}
