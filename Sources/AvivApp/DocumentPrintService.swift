import AppKit

protocol DocumentPrintService {
    func runPageSetup(window: NSWindow?)
    func print(view: NSView, title: String, window: NSWindow?)
}

final class AppKitDocumentPrintService: DocumentPrintService {
    func runPageSetup(window: NSWindow?) {
        let pageLayout = NSPageLayout()
        let printInfo = NSPrintInfo.shared

        if let window {
            pageLayout.beginSheet(with: printInfo, modalFor: window, delegate: nil, didEnd: nil, contextInfo: nil)
        } else {
            pageLayout.runModal(with: printInfo)
        }
    }

    func print(view: NSView, title: String, window: NSWindow?) {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true

        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
