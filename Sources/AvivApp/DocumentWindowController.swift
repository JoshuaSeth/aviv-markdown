import AppKit
import AvivCore
import UniformTypeIdentifiers

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let workspace = EditorWorkspaceView()
    var onRequestNewDocument: ((Any?) -> Void)?
    var onWindowWillClose: ((DocumentWindowController) -> Void)?
    var onDocumentURLAccessed: ((URL) -> Void)?

    var canRevertToSaved: Bool {
        isEdited || documentURL != nil
    }

    var representedDocumentURL: URL? {
        documentURL
    }

    var canReuseForOpenedDocument: Bool {
        documentURL == nil && !isEdited && (workspace.textView.string.isEmpty || workspace.textView.string == MarkdownSamples.starter)
    }

    private let printService: DocumentPrintService
    private var documentURL: URL?
    private var savedText = MarkdownSamples.starter
    private var isEdited = false {
        didSet {
            window?.isDocumentEdited = isEdited
            workspace.updateDocumentTitle(url: documentURL, isEdited: isEdited)
            updateWindowTitle()
        }
    }

    init(printService: DocumentPrintService = AppKitDocumentPrintService()) {
        self.printService = printService
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Aviv"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 520)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.documentTabbingIdentifier
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentView = workspace
        configureToolbar()
        workspace.setDocumentURL(nil)
        workspace.loadMarkdown(MarkdownSamples.starter)
        workspace.updateDocumentTitle(url: nil, isEdited: false)
        updateWindowTitle()
        workspace.textView.onContentChange = { [weak self] text in
            guard let self else { return }
            self.isEdited = text != self.savedText
            self.workspace.updateMetrics()
        }
        workspace.textView.onSelectionChange = { [weak self] in
            self?.workspace.updateMetrics()
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
        do {
            let text = try MarkdownDocumentIO.read(from: url)
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
        onWindowWillClose?(self)
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard isEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes?"
        alert.informativeText = "This document has unsaved changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
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
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func updateWindowTitle() {
        window?.title = documentURL?.lastPathComponent ?? "Untitled"
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "Aviv.Toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newDocument, .openDocument, .saveDocument, .flexibleSpace, .zoomOut, .actualSize, .zoomIn, .flexibleSpace, .bold, .italic, .code, .heading1, .heading2]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newDocument, .openDocument, .saveDocument, .flexibleSpace, .zoomOut, .actualSize, .zoomIn, .flexibleSpace, .bold, .italic, .code, .heading1, .heading2]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self

        switch itemIdentifier {
        case .newDocument:
            item.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "New")
            item.label = "New"
            item.action = #selector(newDocument(_:))
        case .openDocument:
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open")
            item.label = "Open"
            item.action = #selector(openDocument(_:))
        case .saveDocument:
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            item.label = "Save"
            item.action = #selector(saveDocument(_:))
        case .zoomOut:
            item.image = toolbarImage(named: "minus.magnifyingglass", fallback: "textformat.size.smaller", description: "Zoom Out")
            item.label = "Zoom Out"
            item.action = #selector(decreaseTextSize(_:))
        case .actualSize:
            item.image = toolbarImage(named: "1.magnifyingglass", fallback: "text.magnifyingglass", description: "Actual Size")
            item.label = "Actual Size"
            item.action = #selector(resetTextSize(_:))
        case .zoomIn:
            item.image = toolbarImage(named: "plus.magnifyingglass", fallback: "textformat.size.larger", description: "Zoom In")
            item.label = "Zoom In"
            item.action = #selector(increaseTextSize(_:))
        case .bold:
            item.image = NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold")
            item.label = "Bold"
            item.action = #selector(toggleBold(_:))
        case .italic:
            item.image = NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic")
            item.label = "Italic"
            item.action = #selector(toggleItalic(_:))
        case .code:
            item.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Code")
            item.label = "Code"
            item.action = #selector(toggleCode(_:))
        case .heading1:
            item.image = NSImage(systemSymbolName: "h.square", accessibilityDescription: "Heading 1")
            item.label = "Heading 1"
            item.action = #selector(heading1(_:))
        case .heading2:
            item.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Heading 2")
            item.label = "Heading 2"
            item.action = #selector(heading2(_:))
        default:
            return nil
        }

        item.toolTip = item.label
        return item
    }

    private func toolbarImage(named name: String, fallback: String, description: String) -> NSImage? {
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

private extension NSToolbarItem.Identifier {
    static let newDocument = NSToolbarItem.Identifier("Aviv.Toolbar.New")
    static let openDocument = NSToolbarItem.Identifier("Aviv.Toolbar.Open")
    static let saveDocument = NSToolbarItem.Identifier("Aviv.Toolbar.Save")
    static let zoomOut = NSToolbarItem.Identifier("Aviv.Toolbar.ZoomOut")
    static let actualSize = NSToolbarItem.Identifier("Aviv.Toolbar.ActualSize")
    static let zoomIn = NSToolbarItem.Identifier("Aviv.Toolbar.ZoomIn")
    static let bold = NSToolbarItem.Identifier("Aviv.Toolbar.Bold")
    static let italic = NSToolbarItem.Identifier("Aviv.Toolbar.Italic")
    static let code = NSToolbarItem.Identifier("Aviv.Toolbar.Code")
    static let heading1 = NSToolbarItem.Identifier("Aviv.Toolbar.Heading1")
    static let heading2 = NSToolbarItem.Identifier("Aviv.Toolbar.Heading2")
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
            "qmd"
        ]
        var types = markdownExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(.plainText)
        return types
    }
}
