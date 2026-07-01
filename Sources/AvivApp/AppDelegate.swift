import AppKit
import AvivCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let documentSession: DocumentSessionController

    init(documentController: DocumentWindowController? = nil) {
        self.documentSession = DocumentSessionController(initialController: documentController)
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
        return true
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
    }
}
