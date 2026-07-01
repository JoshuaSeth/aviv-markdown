import AppKit
import AvivCore

protocol DocumentPrintService {
    func runPageSetup(window: NSWindow?)
    func print(markdown: String, title: String, format: MarkdownDocumentFormat, baseURL: URL?, window: NSWindow?)
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

    func print(markdown: String, title: String, format: MarkdownDocumentFormat, baseURL: URL?, window: NSWindow?) {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        let margins = format.printMargins
        printInfo.paperSize = format.paperSize
        printInfo.topMargin = margins.top
        printInfo.leftMargin = margins.left
        printInfo.bottomMargin = margins.bottom
        printInfo.rightMargin = margins.right
        printInfo.horizontalPagination = .clip
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let printableWidth = max(320, printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin)
        let printView = MarkdownPrintView(
            markdown: markdown,
            printableWidth: printableWidth,
            format: format,
            baseURL: baseURL
        )

        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
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
