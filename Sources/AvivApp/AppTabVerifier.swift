import AppKit
import AvivCore
import Foundation

enum AppTabVerifier {
    static func runCLI() -> Int32 {
        _ = NSApplication.shared
        NSWindow.allowsAutomaticWindowTabbing = true

        let delegate = AppDelegate()
        NSApp.delegate = delegate
        delegate.buildMenu()

        var failures: [String] = []
        let first = delegate.documentSession.start(with: [])
        drainRunLoop()

        if first.window?.tabbingMode != .preferred {
            failures.append("document windows are not configured for native tabbing")
        }
        if first.window?.tabbingIdentifier != DocumentWindowController.documentTabbingIdentifier {
            failures.append("document windows do not share a tabbing identifier")
        }
        if (first.window?.tabbedWindows?.count ?? 1) > 1 {
            failures.append("a single startup document unexpectedly has multiple visible tabs")
        }

        delegate.newTab(nil)
        drainRunLoop()
        let firstTabCount = first.window?.tabbedWindows?.count ?? 1
        if delegate.documentSession.controllers.count != 2 {
            failures.append("New Tab did not create a second document controller")
        }
        if firstTabCount != 2 {
            failures.append("New Tab did not join the active native tab group; count=\(firstTabCount)")
        }

        let urls = makeFixtureFiles()
        delegate.documentSession.open(urls: urls)
        drainRunLoop()
        let openedTitles = Set(delegate.documentSession.controllers.compactMap { $0.window?.title })
        for url in urls where !openedTitles.contains(url.lastPathComponent) {
            failures.append("opened tab title missing \(url.lastPathComponent)")
        }

        if let tabbedWindows = delegate.documentSession.activeController?.window?.tabbedWindows {
            let tabTitles = Set(tabbedWindows.map(\.title))
            for url in urls where !tabTitles.contains(url.lastPathComponent) {
                failures.append("native tab group missing tab title \(url.lastPathComponent)")
            }

            if tabbedWindows.count < 2 {
                failures.append("native tab group did not retain multiple document tabs")
            }
        } else {
            failures.append("active document does not expose a native tab group")
        }

        let beforeClose = delegate.documentSession.controllers.count
        delegate.closeDocument(nil)
        drainRunLoop()
        if delegate.documentSession.controllers.count != beforeClose - 1 {
            failures.append("Close command did not close exactly the active tab/document")
        }

        let windowA = delegate.documentSession.newWindow(loadStarter: false)
        let windowB = delegate.documentSession.newWindow(loadStarter: false)
        drainRunLoop()
        if windowA.window === windowB.window {
            failures.append("new document windows reused the same NSWindow")
        }
        if delegate.documentSession.controllers.count < 2 {
            failures.append("session does not retain multiple document windows")
        }

        let tabSelectors = [
            "selectPreviousTab:",
            "selectNextTab:",
            "moveTabToNewWindow:",
            "mergeAllWindows:"
        ]
        for selectorName in tabSelectors {
            let selector = Selector(selectorName)
            if windowB.window?.responds(to: selector) != true && NSApp.target(forAction: selector, to: nil, from: nil) == nil {
                failures.append("native tab action is not available: \(selectorName)")
            }
        }

        for controller in delegate.documentSession.controllers {
            controller.close()
        }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        drainRunLoop()

        if failures.isEmpty {
            print("tab-verifier: PASS")
            return 0
        }

        print("tab-verifier: FAIL")
        for failure in failures {
            print("- \(failure)")
        }
        return 1
    }

    private static func makeFixtureFiles() -> [URL] {
        let directory = FileManager.default.temporaryDirectory
        let files = [
            directory.appendingPathComponent("aviv-tab-alpha-\(UUID().uuidString)").appendingPathExtension("md"),
            directory.appendingPathComponent("aviv-tab-beta-\(UUID().uuidString)").appendingPathExtension("md")
        ]

        for (index, url) in files.enumerated() {
            try? "# Tab \(index + 1)\n\nFixture document.".write(to: url, atomically: true, encoding: .utf8)
        }

        return files
    }

    private static func drainRunLoop() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}
