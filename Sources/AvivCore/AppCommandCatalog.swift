import AppKit

public struct AppMenuSpec: Equatable {
    public let title: String
    public let entries: [AppMenuEntry]

    public init(title: String, entries: [AppMenuEntry]) {
        self.title = title
        self.entries = entries
    }
}

public enum AppMenuEntry: Equatable {
    case command(AppCommandSpec)
    case separator
    case submenu(title: String, entries: [AppMenuEntry])
}

public struct AppCommandSpec: Equatable {
    public enum TargetRoute: Equatable {
        case application
        case appDelegate
        case firstResponder
    }

    public let identifier: String
    public let title: String
    public let actionName: String
    public let keyEquivalent: String
    public let modifierMask: NSEvent.ModifierFlags
    public let targetRoute: TargetRoute
    public let tag: Int

    public init(
        identifier: String,
        title: String,
        actionName: String,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [],
        targetRoute: TargetRoute,
        tag: Int = 0
    ) {
        self.identifier = identifier
        self.title = title
        self.actionName = actionName
        self.keyEquivalent = keyEquivalent
        self.modifierMask = modifierMask
        self.targetRoute = targetRoute
        self.tag = tag
    }
}

public enum AppCommandCatalog {
    public static let menus: [AppMenuSpec] = [
        AppMenuSpec(title: "Aviv", entries: [
            .command(appCommand("about", "About Aviv", "orderFrontStandardAboutPanel:")),
            .separator,
            .command(appCommand("hide", "Hide Aviv", "hide:", key: "h", modifiers: [.command])),
            .command(appCommand("hideOthers", "Hide Others", "hideOtherApplications:", key: "h", modifiers: [.command, .option])),
            .command(appCommand("showAll", "Show All", "unhideAllApplications:")),
            .separator,
            .command(appCommand("quit", "Quit Aviv", "terminate:", key: "q", modifiers: [.command]))
        ]),
        AppMenuSpec(title: "File", entries: [
            .command(delegateCommand("new", "New", "newDocument:", key: "n")),
            .command(delegateCommand("newTab", "New Tab", "newTab:", key: "t")),
            .command(delegateCommand("open", "Open...", "openDocument:", key: "o")),
            .separator,
            .command(delegateCommand("close", "Close", "closeDocument:", key: "w")),
            .separator,
            .command(delegateCommand("save", "Save", "saveDocument:", key: "s")),
            .command(delegateCommand("saveAs", "Save As...", "saveDocumentAs:", key: "S", modifiers: [.command, .shift])),
            .command(delegateCommand("revert", "Revert to Saved", "revertDocumentToSaved:")),
            .separator,
            .command(delegateCommand("pageSetup", "Page Setup...", "pageSetup:", key: "P", modifiers: [.command, .shift])),
            .command(delegateCommand("print", "Print...", "printDocument:", key: "p"))
        ]),
        AppMenuSpec(title: "Edit", entries: [
            .command(responderCommand("undo", "Undo", "undo:", key: "z")),
            .command(responderCommand("redo", "Redo", "redo:", key: "Z", modifiers: [.command, .shift])),
            .separator,
            .command(responderCommand("cut", "Cut", "cut:", key: "x")),
            .command(responderCommand("copy", "Copy", "copy:", key: "c")),
            .command(responderCommand("paste", "Paste", "paste:", key: "v")),
            .command(responderCommand("pasteAndMatchStyle", "Paste and Match Style", "pasteAsPlainText:", key: "V", modifiers: [.command, .option, .shift])),
            .command(responderCommand("delete", "Delete", "delete:")),
            .separator,
            .command(responderCommand("selectAll", "Select All", "selectAll:", key: "a")),
            .separator,
            .submenu(title: "Find", entries: [
                .command(findCommand("find", "Find...", NSTextFinder.Action.showFindInterface, key: "f")),
                .command(findCommand("findAndReplace", "Find and Replace...", NSTextFinder.Action.showReplaceInterface, key: "f", modifiers: [.command, .option])),
                .command(findCommand("findNext", "Find Next", NSTextFinder.Action.nextMatch, key: "g")),
                .command(findCommand("findPrevious", "Find Previous", NSTextFinder.Action.previousMatch, key: "G", modifiers: [.command, .shift])),
                .command(findCommand("useSelectionForFind", "Use Selection for Find", NSTextFinder.Action.setSearchString, key: "e")),
                .command(responderCommand("jumpToSelection", "Jump to Selection", "centerSelectionInVisibleArea:", key: "j"))
            ]),
            .submenu(title: "Spelling and Grammar", entries: [
                .command(responderCommand("showSpelling", "Show Spelling and Grammar", "showGuessPanel:", key: ":", modifiers: [.command])),
                .command(responderCommand("checkSpelling", "Check Document Now", "checkSpelling:", key: ";", modifiers: [.command]))
            ])
        ]),
        AppMenuSpec(title: "View", entries: [
            .command(delegateCommand("actualSize", "Actual Size", "resetTextSize:", key: "0")),
            .command(delegateCommand("zoomIn", "Zoom In", "increaseTextSize:", key: "+")),
            .command(delegateCommand("zoomOut", "Zoom Out", "decreaseTextSize:", key: "-"))
        ]),
        AppMenuSpec(title: "Format", entries: [
            .command(delegateCommand("bold", "Bold", "toggleBold:", key: "b")),
            .command(delegateCommand("italic", "Italic", "toggleItalic:", key: "i")),
            .command(delegateCommand("code", "Code", "toggleCode:", key: "`")),
            .separator,
            .command(delegateCommand("heading1", "Heading 1", "heading1:", key: "1")),
            .command(delegateCommand("heading2", "Heading 2", "heading2:", key: "2"))
        ]),
        AppMenuSpec(title: "Window", entries: [
            .command(responderCommand("minimize", "Minimize", "performMiniaturize:", key: "m")),
            .command(responderCommand("zoomWindow", "Zoom", "performZoom:")),
            .separator,
            .command(responderCommand("showPreviousTab", "Show Previous Tab", "selectPreviousTab:", key: "{", modifiers: [.command, .shift])),
            .command(responderCommand("showNextTab", "Show Next Tab", "selectNextTab:", key: "}", modifiers: [.command, .shift])),
            .command(responderCommand("moveTabToNewWindow", "Move Tab to New Window", "moveTabToNewWindow:")),
            .command(responderCommand("mergeAllWindows", "Merge All Windows", "mergeAllWindows:")),
            .separator,
            .command(appCommand("bringAllToFront", "Bring All to Front", "arrangeInFront:"))
        ])
    ]

    public static var commands: [AppCommandSpec] {
        menus.flatMap { commands(in: $0.entries) }
    }

    public static func command(identifier: String) -> AppCommandSpec? {
        commands.first { $0.identifier == identifier }
    }

    private static func commands(in entries: [AppMenuEntry]) -> [AppCommandSpec] {
        entries.flatMap { entry -> [AppCommandSpec] in
            switch entry {
            case .command(let command):
                return [command]
            case .separator:
                return []
            case .submenu(_, let entries):
                return commands(in: entries)
            }
        }
    }

    private static func appCommand(
        _ identifier: String,
        _ title: String,
        _ actionName: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> AppCommandSpec {
        AppCommandSpec(
            identifier: identifier,
            title: title,
            actionName: actionName,
            keyEquivalent: key,
            modifierMask: modifiers,
            targetRoute: .application
        )
    }

    private static func delegateCommand(
        _ identifier: String,
        _ title: String,
        _ actionName: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> AppCommandSpec {
        AppCommandSpec(
            identifier: identifier,
            title: title,
            actionName: actionName,
            keyEquivalent: key,
            modifierMask: key.isEmpty ? [] : modifiers,
            targetRoute: .appDelegate
        )
    }

    private static func responderCommand(
        _ identifier: String,
        _ title: String,
        _ actionName: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> AppCommandSpec {
        AppCommandSpec(
            identifier: identifier,
            title: title,
            actionName: actionName,
            keyEquivalent: key,
            modifierMask: key.isEmpty ? [] : modifiers,
            targetRoute: .firstResponder
        )
    }

    private static func findCommand(
        _ identifier: String,
        _ title: String,
        _ action: NSTextFinder.Action,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> AppCommandSpec {
        AppCommandSpec(
            identifier: identifier,
            title: title,
            actionName: "performFindPanelAction:",
            keyEquivalent: key,
            modifierMask: modifiers,
            targetRoute: .firstResponder,
            tag: action.rawValue
        )
    }
}

public enum AppMenuBuilder {
    public static func makeMenu(
        from menus: [AppMenuSpec] = AppCommandCatalog.menus,
        targetResolver: (AppCommandSpec.TargetRoute) -> AnyObject?
    ) -> NSMenu {
        let mainMenu = NSMenu()
        for menuSpec in menus {
            let menuItem = NSMenuItem()
            let menu = NSMenu(title: menuSpec.title)
            menuItem.submenu = menu
            mainMenu.addItem(menuItem)
            append(menuSpec.entries, to: menu, targetResolver: targetResolver)
        }
        return mainMenu
    }

    private static func append(
        _ entries: [AppMenuEntry],
        to menu: NSMenu,
        targetResolver: (AppCommandSpec.TargetRoute) -> AnyObject?
    ) {
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .command(let command):
                menu.addItem(menuItem(for: command, targetResolver: targetResolver))
            case .submenu(let title, let entries):
                let item = NSMenuItem()
                item.title = title
                let submenu = NSMenu(title: title)
                item.submenu = submenu
                menu.addItem(item)
                append(entries, to: submenu, targetResolver: targetResolver)
            }
        }
    }

    private static func menuItem(
        for command: AppCommandSpec,
        targetResolver: (AppCommandSpec.TargetRoute) -> AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title,
            action: Selector(command.actionName),
            keyEquivalent: command.keyEquivalent
        )
        item.identifier = NSUserInterfaceItemIdentifier(command.identifier)
        item.keyEquivalentModifierMask = command.modifierMask
        item.target = targetResolver(command.targetRoute)
        item.tag = command.tag
        return item
    }
}
