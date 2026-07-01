import AppKit
import Foundation

protocol RecentDocumentManaging: AnyObject {
    var recentDocumentURLs: [URL] { get }
    func noteNewRecentDocumentURL(_ url: URL)
    func clearRecentDocuments()
}

final class AppKitRecentDocumentManager: RecentDocumentManaging {
    var recentDocumentURLs: [URL] {
        NSDocumentController.shared.recentDocumentURLs
    }

    func noteNewRecentDocumentURL(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func clearRecentDocuments() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}
