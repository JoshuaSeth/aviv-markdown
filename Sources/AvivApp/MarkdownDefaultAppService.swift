import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

enum MarkdownDefaultAppService {
    private static let neverAskKey = "Aviv.NeverAskDefaultMarkdownApp"
    private static let fallbackBundleID = "local.aviv.markdown"
    private static let roles: [LSRolesMask] = [.all, .editor, .viewer]
    private static let markdownContentTypes = [
        "net.daringfireball.markdown",
        "io.typora.markdown"
    ]
    private static let markdownExtensions = [
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
    private static let genericTextContentTypes = Set([
        "public.plain-text",
        "public.text",
        "public.data",
        "public.item",
        "public.content"
    ])

    static func presentPromptIfNeeded(window: NSWindow?, defaults: UserDefaults = .standard) {
        guard !shouldSkipDefaultAppPrompt else { return }
        guard !defaults.bool(forKey: neverAskKey) else { return }
        guard !isCurrentAppDefaultForMarkdown() else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Open Markdown files with Aviv?"
        alert.informativeText = "Aviv can become the default app for .md, .markdown, and related Markdown files so double-clicking a document opens this clean editor."
        alert.addButton(withTitle: "Use Aviv")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Never Show Again")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .alertFirstButtonReturn:
                if !setCurrentAppAsDefaultForMarkdown() {
                    presentFailure(window: window)
                }
            case .alertThirdButtonReturn:
                defaults.set(true, forKey: neverAskKey)
            default:
                break
            }
        }

        if let window {
            alert.beginSheetModal(for: window) { response in
                handleResponse(response)
            }
        } else {
            handleResponse(alert.runModal())
        }
    }

    static func isCurrentAppDefaultForMarkdown(bundleID: String = currentBundleID) -> Bool {
        defaultableContentTypes().allSatisfy { contentType in
            roles.allSatisfy { role in
                defaultHandler(for: contentType, role: role) == bundleID
            }
        }
    }

    @discardableResult
    static func setCurrentAppAsDefaultForMarkdown(bundleID: String = currentBundleID) -> Bool {
        registerCurrentBundleIfPossible()

        var succeeded = true
        for contentType in defaultableContentTypes() {
            for role in roles {
                let status = LSSetDefaultRoleHandlerForContentType(contentType as CFString, role, bundleID as CFString)
                if status != noErr {
                    succeeded = false
                }
            }
        }
        return succeeded && isCurrentAppDefaultForMarkdown(bundleID: bundleID)
    }

    static func verifyPromptLogicForCLI() -> Int32 {
        guard !defaultableContentTypes().isEmpty else {
            fputs("default-app-verifier: no Markdown content types resolved\n", stderr)
            return 1
        }

        let bundleID = currentBundleID
        guard !bundleID.isEmpty else {
            fputs("default-app-verifier: empty bundle identifier\n", stderr)
            return 1
        }

        print("default-app-verifier: PASS bundle=\(bundleID) types=\(defaultableContentTypes().count)")
        return 0
    }

    private static var currentBundleID: String {
        Bundle.main.bundleIdentifier ?? fallbackBundleID
    }

    private static var shouldSkipDefaultAppPrompt: Bool {
        ProcessInfo.processInfo.environment["AVIV_SKIP_DEFAULT_APP_PROMPT"] == "1" ||
            ProcessInfo.processInfo.environment["AVIV_UI_VERIFY"] == "1"
    }

    private static func presentFailure(window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Aviv could not update the default app."
        alert.informativeText = "You can still set Aviv from Finder: choose a Markdown file, open Get Info, choose Aviv under Open With, then select Change All."
        alert.addButton(withTitle: "OK")

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func defaultHandler(for contentType: String, role: LSRolesMask) -> String? {
        guard let unmanaged = LSCopyDefaultRoleHandlerForContentType(contentType as CFString, role) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }

    private static func defaultableContentTypes() -> [String] {
        var result: [String] = []
        for contentType in markdownContentTypes + markdownExtensions.compactMap({ UTType(filenameExtension: $0)?.identifier }) {
            guard !genericTextContentTypes.contains(contentType), !result.contains(contentType) else {
                continue
            }
            result.append(contentType)
        }
        return result
    }

    private static func registerCurrentBundleIfPossible() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return }
        LSRegisterURL(bundleURL as CFURL, true)
    }
}
