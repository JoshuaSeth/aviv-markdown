import AppKit
import XCTest
@testable import AvivCore

final class AppCommandCatalogTests: XCTestCase {
    func testStandardDocumentCommandShortcutsArePresent() {
        assertCommand("new", title: "New", action: "newDocument:", key: "n", modifiers: [.command], target: .appDelegate)
        assertCommand("newTab", title: "New Tab", action: "newTab:", key: "t", modifiers: [.command], target: .appDelegate)
        assertCommand("open", title: "Open...", action: "openDocument:", key: "o", modifiers: [.command], target: .appDelegate)
        assertCommand("clearRecentDocuments", title: "Clear Menu", action: "clearRecentDocuments:", key: "", modifiers: [], target: .appDelegate)
        assertCommand("close", title: "Close", action: "closeDocument:", key: "w", modifiers: [.command], target: .appDelegate)
        assertCommand("save", title: "Save", action: "saveDocument:", key: "s", modifiers: [.command], target: .appDelegate)
        assertCommand("saveAs", title: "Save As...", action: "saveDocumentAs:", key: "S", modifiers: [.command, .shift], target: .appDelegate)
        assertCommand("pageSetup", title: "Page Setup...", action: "pageSetup:", key: "P", modifiers: [.command, .shift], target: .appDelegate)
        assertCommand("print", title: "Print...", action: "printDocument:", key: "p", modifiers: [.command], target: .appDelegate)

        assertCommand("undo", title: "Undo", action: "undo:", key: "z", modifiers: [.command], target: .firstResponder)
        assertCommand("redo", title: "Redo", action: "redo:", key: "Z", modifiers: [.command, .shift], target: .firstResponder)
        assertCommand("cut", title: "Cut", action: "cut:", key: "x", modifiers: [.command], target: .firstResponder)
        assertCommand("copy", title: "Copy", action: "copy:", key: "c", modifiers: [.command], target: .firstResponder)
        assertCommand("paste", title: "Paste", action: "paste:", key: "v", modifiers: [.command], target: .firstResponder)
        assertCommand("pasteAndMatchStyle", title: "Paste and Match Style", action: "pasteAsPlainText:", key: "V", modifiers: [.command, .option, .shift], target: .firstResponder)
        assertCommand("selectAll", title: "Select All", action: "selectAll:", key: "a", modifiers: [.command], target: .firstResponder)

        assertCommand("find", title: "Find...", action: "performFindPanelAction:", key: "f", modifiers: [.command], target: .firstResponder)
        assertCommand("findNext", title: "Find Next", action: "performFindPanelAction:", key: "g", modifiers: [.command], target: .firstResponder)
        assertCommand("findPrevious", title: "Find Previous", action: "performFindPanelAction:", key: "G", modifiers: [.command, .shift], target: .firstResponder)
        assertCommand("useSelectionForFind", title: "Use Selection for Find", action: "performFindPanelAction:", key: "e", modifiers: [.command], target: .firstResponder)
        assertCommand("jumpToSelection", title: "Jump to Selection", action: "centerSelectionInVisibleArea:", key: "j", modifiers: [.command], target: .firstResponder)

        assertCommand("actualSize", title: "Actual Size", action: "resetTextSize:", key: "0", modifiers: [.command], target: .appDelegate)
        assertCommand("zoomIn", title: "Zoom In", action: "increaseTextSize:", key: "+", modifiers: [.command], target: .appDelegate)
        assertCommand("zoomOut", title: "Zoom Out", action: "decreaseTextSize:", key: "-", modifiers: [.command], target: .appDelegate)

        assertCommand("showPreviousTab", title: "Show Previous Tab", action: "selectPreviousTab:", key: "{", modifiers: [.command, .shift], target: .firstResponder)
        assertCommand("showNextTab", title: "Show Next Tab", action: "selectNextTab:", key: "}", modifiers: [.command, .shift], target: .firstResponder)
        assertCommand("moveTabToNewWindow", title: "Move Tab to New Window", action: "moveTabToNewWindow:", key: "", modifiers: [], target: .firstResponder)
        assertCommand("mergeAllWindows", title: "Merge All Windows", action: "mergeAllWindows:", key: "", modifiers: [], target: .firstResponder)
    }

    func testCatalogProvidesAtLeastTwentyStandardCommandsWithoutShortcutCollisions() {
        XCTAssertGreaterThanOrEqual(AppCommandCatalog.commands.count, 20)

        var shortcutsBySignature: [String: String] = [:]
        for command in AppCommandCatalog.commands where !command.keyEquivalent.isEmpty {
            let signature = shortcutSignature(for: command)
            if let previous = shortcutsBySignature[signature] {
                XCTFail("Shortcut collision: \(previous) and \(command.identifier) both use \(signature)")
            }
            shortcutsBySignature[signature] = command.identifier
        }
    }

    func testFindCommandsCarryNativeTextFinderTags() {
        XCTAssertEqual(AppCommandCatalog.command(identifier: "find")?.tag, NSTextFinder.Action.showFindInterface.rawValue)
        XCTAssertEqual(AppCommandCatalog.command(identifier: "findAndReplace")?.tag, NSTextFinder.Action.showReplaceInterface.rawValue)
        XCTAssertEqual(AppCommandCatalog.command(identifier: "findNext")?.tag, NSTextFinder.Action.nextMatch.rawValue)
        XCTAssertEqual(AppCommandCatalog.command(identifier: "findPrevious")?.tag, NSTextFinder.Action.previousMatch.rawValue)
        XCTAssertEqual(AppCommandCatalog.command(identifier: "useSelectionForFind")?.tag, NSTextFinder.Action.setSearchString.rawValue)
    }

    func testMenuBuilderKeepsEveryCatalogCommandAddressable() {
        let appTarget = NSObject()
        let delegateTarget = NSObject()
        let menu = AppMenuBuilder.makeMenu { route in
            switch route {
            case .application:
                return appTarget
            case .appDelegate:
                return delegateTarget
            case .firstResponder:
                return nil
            }
        }

        let builtItems = flatten(menu.items).filter { $0.action != nil }
        let builtIdentifiers = Set(builtItems.compactMap { $0.identifier?.rawValue })
        let catalogIdentifiers = Set(AppCommandCatalog.commands.map(\.identifier))

        XCTAssertEqual(builtIdentifiers, catalogIdentifiers)
        XCTAssertTrue(builtItems.contains { $0.identifier?.rawValue == "save" && $0.target === delegateTarget })
        XCTAssertTrue(builtItems.contains { $0.identifier?.rawValue == "print" && $0.target === delegateTarget })
        XCTAssertTrue(builtItems.contains { $0.identifier?.rawValue == "paste" && $0.target == nil })
    }

    private func assertCommand(
        _ identifier: String,
        title: String,
        action: String,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        target: AppCommandSpec.TargetRoute
    ) {
        let command = AppCommandCatalog.command(identifier: identifier)
        XCTAssertEqual(command?.title, title)
        XCTAssertEqual(command?.actionName, action)
        XCTAssertEqual(command?.keyEquivalent, key)
        XCTAssertEqual(normalized(command?.modifierMask ?? []), normalized(modifiers))
        XCTAssertEqual(command?.targetRoute, target)
    }

    private func shortcutSignature(for command: AppCommandSpec) -> String {
        "\(normalized(command.modifierMask).rawValue):\(command.keyEquivalent.lowercased())"
    }

    private func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }

    private func flatten(_ items: [NSMenuItem]) -> [NSMenuItem] {
        items.flatMap { item -> [NSMenuItem] in
            guard let submenu = item.submenu else { return [item] }
            return [item] + flatten(submenu.items)
        }
    }
}
