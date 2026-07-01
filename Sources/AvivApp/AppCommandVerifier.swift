import AppKit
import AvivCore
import Foundation

enum AppCommandVerifier {
    static func runCLI() -> Int32 {
        _ = NSApplication.shared
        let printService = RecordingPrintService()
        let recentDocuments = RecordingRecentDocumentManager()
        let controller = DocumentWindowController(printService: printService)
        let delegate = AppDelegate(documentController: controller, recentDocuments: recentDocuments)
        NSApp.delegate = delegate
        delegate.buildMenu()
        controller.window?.makeFirstResponder(controller.workspace.textView)

        var failures: [String] = []
        failures.append(contentsOf: verifyMenuStructure())
        failures.append(contentsOf: verifyCommandTargets(delegate: delegate, controller: controller))
        failures.append(contentsOf: verifyBehavior(
            delegate: delegate,
            controller: controller,
            printService: printService,
            recentDocuments: recentDocuments
        ))

        controller.close()

        if failures.isEmpty {
            print("command-verifier: PASS (\(AppCommandCatalog.commands.count) commands)")
            return 0
        }

        print("command-verifier: FAIL")
        for failure in failures {
            print("- \(failure)")
        }
        return 1
    }

    private static func verifyMenuStructure() -> [String] {
        guard let menu = NSApp.mainMenu else {
            return ["main menu was not installed"]
        }

        let builtItems = commandItems(in: menu.items)
        let builtIdentifiers = Set(builtItems.compactMap { $0.identifier?.rawValue })
        let catalogIdentifiers = Set(AppCommandCatalog.commands.map(\.identifier))
        var failures: [String] = []

        if builtIdentifiers != catalogIdentifiers {
            failures.append("built menu identifiers do not match command catalog")
        }

        for command in AppCommandCatalog.commands {
            guard let item = builtItems.first(where: { $0.identifier?.rawValue == command.identifier }) else {
                failures.append("missing menu item for \(command.identifier)")
                continue
            }
            if item.title != command.title {
                failures.append("\(command.identifier) title is \(item.title), expected \(command.title)")
            }
            if item.action != Selector(command.actionName) {
                failures.append("\(command.identifier) action is \(String(describing: item.action)), expected \(command.actionName)")
            }
            if item.keyEquivalent != command.keyEquivalent {
                failures.append("\(command.identifier) key is \(item.keyEquivalent), expected \(command.keyEquivalent)")
            }
            if normalized(item.keyEquivalentModifierMask) != normalized(command.modifierMask) {
                failures.append("\(command.identifier) modifiers are \(item.keyEquivalentModifierMask), expected \(command.modifierMask)")
            }
            if item.tag != command.tag {
                failures.append("\(command.identifier) tag is \(item.tag), expected \(command.tag)")
            }
        }

        return failures
    }

    private static func verifyCommandTargets(delegate: AppDelegate, controller: DocumentWindowController) -> [String] {
        var failures: [String] = []

        for command in AppCommandCatalog.commands {
            let selector = Selector(command.actionName)
            switch command.targetRoute {
            case .application:
                if !NSApp.responds(to: selector) {
                    failures.append("NSApplication does not respond to \(command.actionName) for \(command.identifier)")
                }
            case .appDelegate:
                if !delegate.responds(to: selector) {
                    failures.append("AppDelegate does not respond to \(command.actionName) for \(command.identifier)")
                }
            case .firstResponder:
                if !responderChainCanHandle(selector, controller: controller) {
                    failures.append("document responder chain does not handle \(command.actionName) for \(command.identifier)")
                }
            }
        }

        return failures
    }

    private static func verifyBehavior(
        delegate: AppDelegate,
        controller: DocumentWindowController,
        printService: RecordingPrintService,
        recentDocuments: RecordingRecentDocumentManager
    ) -> [String] {
        var failures: [String] = []

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("aviv-command-verifier-\(UUID().uuidString)")
                .appendingPathExtension("md")
            try "old".write(to: url, atomically: true, encoding: .utf8)
            controller.open(url: url)
            if recentDocuments.recentDocumentURLs.first != url {
                failures.append("Opening a document did not add it to recent documents")
            }
            controller.workspace.textView.loadMarkdown("changed")
            delegate.saveDocument(nil)
            if recentDocuments.recentDocumentURLs.first != url {
                failures.append("Saving a document did not keep it at the top of recent documents")
            }
            let saved = try String(contentsOf: url, encoding: .utf8)
            if saved != "changed" {
                failures.append("Save command did not write the active document text")
            }
            try? FileManager.default.removeItem(at: url)
        } catch {
            failures.append("Save command verification threw \(error)")
        }

        delegate.pageSetup(nil)
        delegate.printDocument(nil)
        if printService.pageSetupCount != 1 {
            failures.append("Page Setup command did not reach print service")
        }
        if printService.printCount != 1 {
            failures.append("Print command did not reach print service")
        }

        let zoomSource = controller.workspace.textView.string
        let startScale = controller.workspace.textView.styler.theme.viewScale
        delegate.increaseTextSize(nil)
        if controller.workspace.textView.styler.theme.viewScale <= startScale {
            failures.append("Zoom In command did not increase view scale")
        }
        delegate.decreaseTextSize(nil)
        delegate.resetTextSize(nil)
        if abs(controller.workspace.textView.styler.theme.viewScale - MarkdownTheme.defaultViewScale) > 0.001 {
            failures.append("Actual Size command did not reset view scale")
        }
        if controller.workspace.textView.string != zoomSource {
            failures.append("Zoom commands changed the markdown source")
        }

        controller.workspace.textView.loadMarkdown("word")
        controller.workspace.textView.setSelectedRange(NSRange(location: 0, length: 4))
        delegate.toggleBold(nil)
        if controller.workspace.textView.string != "**word**" {
            failures.append("Bold command did not wrap selected text")
        }

        failures.append(contentsOf: verifyOpenRecentMenu(delegate: delegate, recentDocuments: recentDocuments))

        return failures
    }

    private static func verifyOpenRecentMenu(
        delegate: AppDelegate,
        recentDocuments: RecordingRecentDocumentManager
    ) -> [String] {
        var failures: [String] = []
        guard
            let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu,
            let openRecentMenu = fileMenu.item(withTitle: "Open Recent")?.submenu
        else {
            return ["Open Recent submenu is missing from the File menu"]
        }

        let recentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aviv-open-recent-\(UUID().uuidString)")
            .appendingPathExtension("md")

        do {
            try "# Recent\n\nOpened from native menu.".write(to: recentURL, atomically: true, encoding: .utf8)
            recentDocuments.noteNewRecentDocumentURL(recentURL)
            openRecentMenu.delegate?.menuNeedsUpdate?(openRecentMenu)

            guard let recentItem = openRecentMenu.items.first(where: { ($0.representedObject as? URL) == recentURL }) else {
                try? FileManager.default.removeItem(at: recentURL)
                return ["Open Recent submenu did not render the recorded recent file"]
            }

            if recentItem.action != #selector(AppDelegate.openRecentDocument(_:)) {
                failures.append("Open Recent file item does not target openRecentDocument:")
            }
            if recentItem.title != recentURL.lastPathComponent {
                failures.append("Open Recent file item title is \(recentItem.title), expected \(recentURL.lastPathComponent)")
            }

            delegate.openRecentDocument(recentItem)
            if !delegate.documentSession.controllers.contains(where: { $0.representedDocumentURL == recentURL }) {
                failures.append("Open Recent item did not open the represented document")
            }

            delegate.clearRecentDocuments(nil)
            if !recentDocuments.recentDocumentURLs.isEmpty {
                failures.append("Clear Menu did not clear recent documents")
            }
            openRecentMenu.delegate?.menuNeedsUpdate?(openRecentMenu)
            if openRecentMenu.items.first?.title != "No Recent Documents" {
                failures.append("Open Recent submenu did not show the empty state after clearing")
            }
            if openRecentMenu.items.last?.isEnabled == true {
                failures.append("Clear Menu stayed enabled after clearing recent documents")
            }
        } catch {
            failures.append("Open Recent verification threw \(error)")
        }

        try? FileManager.default.removeItem(at: recentURL)
        return failures
    }

    private static func responderChainCanHandle(_ selector: Selector, controller: DocumentWindowController) -> Bool {
        let textView = controller.workspace.textView
        if textView.responds(to: selector) {
            return true
        }
        if controller.window?.responds(to: selector) == true {
            return true
        }
        if selector == Selector(("undo:")) || selector == Selector(("redo:")) {
            return textView.undoManager != nil
        }
        return NSApp.target(forAction: selector, to: nil, from: nil) != nil
    }

    private static func commandItems(in items: [NSMenuItem]) -> [NSMenuItem] {
        items.flatMap { item -> [NSMenuItem] in
            var result: [NSMenuItem] = []
            if item.action != nil {
                result.append(item)
            }
            if let submenu = item.submenu {
                result.append(contentsOf: commandItems(in: submenu.items))
            }
            return result
        }
    }

    private static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }
}

private final class RecordingPrintService: DocumentPrintService {
    var pageSetupCount = 0
    var printCount = 0

    func runPageSetup(window: NSWindow?) {
        pageSetupCount += 1
    }

    func print(markdown: String, title: String, format: MarkdownDocumentFormat, baseURL: URL?, window: NSWindow?) {
        printCount += 1
    }
}

private final class RecordingRecentDocumentManager: RecentDocumentManaging {
    private(set) var recentDocumentURLs: [URL] = []

    func noteNewRecentDocumentURL(_ url: URL) {
        recentDocumentURLs.removeAll { normalized($0) == normalized(url) }
        recentDocumentURLs.insert(url, at: 0)
    }

    func clearRecentDocuments() {
        recentDocumentURLs.removeAll()
    }

    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
