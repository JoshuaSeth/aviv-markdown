import AppKit
import AvivCore

final class DocumentSessionController {
    private(set) var controllers: [DocumentWindowController] = []
    private let printServiceFactory: () -> DocumentPrintService

    init(
        initialController: DocumentWindowController? = nil,
        printServiceFactory: @escaping () -> DocumentPrintService = { AppKitDocumentPrintService() }
    ) {
        self.printServiceFactory = printServiceFactory
        if let initialController {
            adopt(initialController)
        }
    }

    var activeController: DocumentWindowController? {
        if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow,
           let controller = controllers.first(where: { $0.window === keyWindow }) {
            return controller
        }

        if let visibleController = controllers.last(where: { $0.window?.isVisible == true }) {
            return visibleController
        }

        return controllers.last
    }

    @discardableResult
    func start(with urls: [URL]) -> DocumentWindowController {
        if urls.isEmpty {
            return newWindow(loadStarter: true)
        }

        let controller = newWindow(loadStarter: false)
        open(urls: urls)
        return controller
    }

    @discardableResult
    func newWindow(loadStarter: Bool = false) -> DocumentWindowController {
        let controller = makeController()
        if !loadStarter {
            controller.resetToEmptyDocument()
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    @discardableResult
    func newTab(opening url: URL? = nil) -> DocumentWindowController {
        guard let active = activeController, let activeWindow = active.window else {
            let controller = newWindow(loadStarter: false)
            if let url {
                controller.open(url: url)
            }
            return controller
        }

        let controller = makeController()
        controller.resetToEmptyDocument()
        if let url {
            controller.open(url: url)
        }

        guard let tabWindow = controller.window else {
            return controller
        }

        tabWindow.tabbingIdentifier = activeWindow.tabbingIdentifier
        activeWindow.addTabbedWindow(tabWindow, ordered: .above)
        controller.showWindow(nil)
        tabWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    func open(urls: [URL]) {
        guard !urls.isEmpty else { return }

        for url in urls {
            if let existing = existingController(for: url) {
                activate(existing)
                continue
            }

            if let active = activeController, active.canReuseForOpenedDocument {
                active.open(url: url)
                activate(active)
                continue
            }

            newTab(opening: url)
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentWindowController.markdownContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if let window = activeController?.window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK else { return }
                self?.open(urls: panel.urls)
            }
        } else if panel.runModal() == .OK {
            open(urls: panel.urls)
        }
    }

    func remove(_ controller: DocumentWindowController) {
        controllers.removeAll { $0 === controller }
    }

    private func makeController() -> DocumentWindowController {
        let controller = DocumentWindowController(printService: printServiceFactory())
        adopt(controller)
        return controller
    }

    private func adopt(_ controller: DocumentWindowController) {
        guard !controllers.contains(where: { $0 === controller }) else { return }
        controllers.append(controller)
        controller.onRequestNewDocument = { [weak self] sender in
            self?.newWindow(loadStarter: false)
        }
        controller.onWindowWillClose = { [weak self] controller in
            self?.remove(controller)
        }
        controller.window?.tabbingIdentifier = DocumentWindowController.documentTabbingIdentifier
        controller.window?.tabbingMode = .preferred
    }

    private func existingController(for url: URL) -> DocumentWindowController? {
        let target = normalized(url)
        return controllers.first { controller in
            guard let representedURL = controller.representedDocumentURL else { return false }
            return normalized(representedURL) == target
        }
    }

    private func activate(_ controller: DocumentWindowController) {
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
