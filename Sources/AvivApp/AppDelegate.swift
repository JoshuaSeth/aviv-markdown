import AppKit
import AvivCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    let documentSession: DocumentSessionController
    private weak var openRecentMenu: NSMenu?

    init(
        documentController: DocumentWindowController? = nil,
        recentDocuments: RecentDocumentManaging = AppKitRecentDocumentManager()
    ) {
        self.documentSession = DocumentSessionController(
            initialController: documentController,
            recentDocuments: recentDocuments
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        buildMenu()
        let launchURLs = launchFileURLs()
        if documentSession.controllers.isEmpty {
            _ = documentSession.start(with: launchURLs)
        } else {
            documentSession.open(urls: launchURLs)
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            MarkdownDefaultAppService.presentPromptIfNeeded(window: self?.documentSession.activeController?.window)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        documentSession.open(urls: [URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard !filenames.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        documentSession.open(urls: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func newDocument(_ sender: Any?) {
        documentSession.newWindow(loadStarter: false)
    }

    @objc func newTab(_ sender: Any?) {
        documentSession.newTab()
    }

    @objc func openDocument(_ sender: Any?) {
        documentSession.presentOpenPanel()
    }

    @objc func openRecentDocument(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let url = item.representedObject as? URL else { return }
        documentSession.open(urls: [url])
    }

    @objc func clearRecentDocuments(_ sender: Any?) {
        documentSession.recentDocuments.clearRecentDocuments()
        rebuildOpenRecentMenu()
    }

    @objc func saveDocument(_ sender: Any?) {
        activeDocumentController()?.saveDocument(sender)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        activeDocumentController()?.saveDocumentAs(sender)
    }

    @objc func closeDocument(_ sender: Any?) {
        activeDocumentController()?.closeDocument(sender)
    }

    @objc func revertDocumentToSaved(_ sender: Any?) {
        activeDocumentController()?.revertDocumentToSaved(sender)
    }

    @objc func pageSetup(_ sender: Any?) {
        activeDocumentController()?.pageSetup(sender)
    }

    @objc func printDocument(_ sender: Any?) {
        activeDocumentController()?.printDocument(sender)
    }

    @objc func increaseTextSize(_ sender: Any?) {
        activeDocumentController()?.increaseTextSize(sender)
    }

    @objc func decreaseTextSize(_ sender: Any?) {
        activeDocumentController()?.decreaseTextSize(sender)
    }

    @objc func resetTextSize(_ sender: Any?) {
        activeDocumentController()?.resetTextSize(sender)
    }

    @objc func toggleBold(_ sender: Any?) {
        activeDocumentController()?.workspace.textView.wrapSelection(prefix: "**", suffix: "**")
    }

    @objc func toggleItalic(_ sender: Any?) {
        activeDocumentController()?.workspace.textView.wrapSelection(prefix: "_", suffix: "_")
    }

    @objc func toggleCode(_ sender: Any?) {
        activeDocumentController()?.workspace.textView.wrapSelection(prefix: "`", suffix: "`")
    }

    @objc func heading1(_ sender: Any?) {
        activeDocumentController()?.workspace.textView.makeHeading(level: 1)
    }

    @objc func heading2(_ sender: Any?) {
        activeDocumentController()?.workspace.textView.makeHeading(level: 2)
    }

    private func launchFileURLs() -> [URL] {
        CommandLine.arguments.dropFirst()
            .filter { !$0.hasPrefix("--") }
            .map { URL(fileURLWithPath: $0) }
    }

    private func activeDocumentController() -> DocumentWindowController? {
        documentSession.activeController
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(revertDocumentToSaved(_:)) {
            return activeDocumentController()?.canRevertToSaved ?? false
        }
        if menuItem.action == #selector(openRecentDocument(_:)) {
            return menuItem.representedObject is URL
        }
        if menuItem.action == #selector(clearRecentDocuments(_:)) {
            return !documentSession.recentDocuments.recentDocumentURLs.isEmpty
        }
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === openRecentMenu {
            rebuildOpenRecentMenu()
        }
    }

    func buildMenu() {
        NSApp.mainMenu = AppMenuBuilder.makeMenu { [weak self] route in
            switch route {
            case .application:
                return NSApp
            case .appDelegate:
                return self
            case .firstResponder:
                return nil
            }
        }
        NSApp.windowsMenu = NSApp.mainMenu?.item(withTitle: "Window")?.submenu
        configureOpenRecentMenu()
    }

    private func configureOpenRecentMenu() {
        guard
            let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu,
            let recentMenu = fileMenu.item(withTitle: "Open Recent")?.submenu
        else {
            return
        }

        openRecentMenu = recentMenu
        recentMenu.autoenablesItems = false
        recentMenu.delegate = self
        rebuildOpenRecentMenu()
    }

    private func rebuildOpenRecentMenu() {
        guard let menu = openRecentMenu else { return }

        menu.removeAllItems()
        let urls = documentSession.recentDocuments.recentDocumentURLs

        if urls.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for url in urls.prefix(15) {
                let item = NSMenuItem(
                    title: displayName(for: url),
                    action: #selector(openRecentDocument(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = url
                item.toolTip = url.path
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let clearItem = NSMenuItem(
            title: "Clear Menu",
            action: #selector(clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clearItem.identifier = NSUserInterfaceItemIdentifier("clearRecentDocuments")
        clearItem.target = self
        clearItem.keyEquivalentModifierMask = []
        clearItem.isEnabled = !urls.isEmpty
        menu.addItem(clearItem)
    }

    private func displayName(for url: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: url.path)
        return displayName.isEmpty ? url.lastPathComponent : displayName
    }
}
