namespace Aviv.Windows.Core;

[Flags]
public enum AvivKeyModifiers
{
    None = 0,
    Ctrl = 1,
    Shift = 2,
    Alt = 4
}

public enum AppCommandRoute
{
    Application,
    AppViewModel,
    Editor
}

public sealed record AppCommandSpec(
    string Identifier,
    string Title,
    string ActionName,
    string Key = "",
    AvivKeyModifiers Modifiers = AvivKeyModifiers.None,
    AppCommandRoute Route = AppCommandRoute.Editor,
    int Tag = 0);

public abstract record AppMenuEntry
{
    public sealed record Command(AppCommandSpec Spec) : AppMenuEntry;
    public sealed record Separator : AppMenuEntry;
    public sealed record Submenu(string Title, IReadOnlyList<AppMenuEntry> Entries) : AppMenuEntry;
}

public sealed record AppMenuSpec(string Title, IReadOnlyList<AppMenuEntry> Entries);

public static class AppCommandCatalog
{
    public static IReadOnlyList<AppMenuSpec> Menus { get; } =
    [
        new("Aviv",
        [
            App("about", "About Aviv", "ShowAbout"),
            Sep(),
            App("quit", "Quit Aviv", "Quit", "Q", AvivKeyModifiers.Ctrl)
        ]),
        new("File",
        [
            ViewModel("new", "New", "NewDocument", "N"),
            ViewModel("newTab", "New Tab", "NewTab", "T"),
            ViewModel("open", "Open...", "OpenDocument", "O"),
            Sep(),
            ViewModel("close", "Close", "CloseDocument", "W"),
            Sep(),
            ViewModel("save", "Save", "SaveDocument", "S"),
            ViewModel("saveAs", "Save As...", "SaveDocumentAs", "S", AvivKeyModifiers.Ctrl | AvivKeyModifiers.Shift),
            ViewModel("revert", "Revert to Saved", "RevertDocument"),
            Sep(),
            ViewModel("pageSetup", "Page Setup...", "PageSetup", "P", AvivKeyModifiers.Ctrl | AvivKeyModifiers.Shift),
            ViewModel("print", "Print...", "PrintDocument", "P")
        ]),
        new("Edit",
        [
            Editor("undo", "Undo", "Undo", "Z"),
            Editor("redo", "Redo", "Redo", "Z", AvivKeyModifiers.Ctrl | AvivKeyModifiers.Shift),
            Sep(),
            Editor("cut", "Cut", "Cut", "X"),
            Editor("copy", "Copy", "Copy", "C"),
            Editor("paste", "Paste", "Paste", "V"),
            Editor("pasteAndMatchStyle", "Paste and Match Style", "PastePlainText", "V", AvivKeyModifiers.Ctrl | AvivKeyModifiers.Alt | AvivKeyModifiers.Shift),
            Editor("delete", "Delete", "Delete"),
            Sep(),
            Editor("selectAll", "Select All", "SelectAll", "A"),
            Sep(),
            Submenu("Find",
            [
                Editor("find", "Find...", "ShowFind", "F"),
                Editor("findAndReplace", "Find and Replace...", "ShowReplace", "F", AvivKeyModifiers.Ctrl | AvivKeyModifiers.Alt),
                Editor("findNext", "Find Next", "FindNext", "G"),
                Editor("findPrevious", "Find Previous", "FindPrevious", "G", AvivKeyModifiers.Ctrl | AvivKeyModifiers.Shift),
                Editor("useSelectionForFind", "Use Selection for Find", "UseSelectionForFind", "E"),
                Editor("jumpToSelection", "Jump to Selection", "JumpToSelection", "J")
            ])
        ]),
        new("View",
        [
            ViewModel("actualSize", "Actual Size", "ResetTextSize", "0"),
            ViewModel("zoomIn", "Zoom In", "IncreaseTextSize", "+"),
            ViewModel("zoomOut", "Zoom Out", "DecreaseTextSize", "-")
        ]),
        new("Format",
        [
            ViewModel("bold", "Bold", "ToggleBold", "B"),
            ViewModel("italic", "Italic", "ToggleItalic", "I"),
            ViewModel("code", "Code", "ToggleCode", "`"),
            Sep(),
            ViewModel("heading1", "Heading 1", "Heading1", "1"),
            ViewModel("heading2", "Heading 2", "Heading2", "2")
        ]),
        new("Window",
        [
            ViewModel("minimize", "Minimize", "MinimizeWindow", "M"),
            ViewModel("zoomWindow", "Zoom", "ZoomWindow"),
            Sep(),
            ViewModel("showPreviousTab", "Show Previous Tab", "ShowPreviousTab", "Tab", AvivKeyModifiers.Ctrl | AvivKeyModifiers.Shift),
            ViewModel("showNextTab", "Show Next Tab", "ShowNextTab", "Tab"),
            ViewModel("moveTabToNewWindow", "Move Tab to New Window", "MoveTabToNewWindow"),
            ViewModel("mergeAllWindows", "Merge All Windows", "MergeAllWindows"),
            Sep(),
            App("bringAllToFront", "Bring All to Front", "BringAllToFront")
        ])
    ];

    public static IReadOnlyList<AppCommandSpec> Commands => Menus.SelectMany(menu => CommandsIn(menu.Entries)).ToArray();

    public static AppCommandSpec? Command(string identifier)
    {
        return Commands.FirstOrDefault(command => command.Identifier == identifier);
    }

    private static IEnumerable<AppCommandSpec> CommandsIn(IEnumerable<AppMenuEntry> entries)
    {
        foreach (var entry in entries)
        {
            switch (entry)
            {
                case AppMenuEntry.Command command:
                    yield return command.Spec;
                    break;
                case AppMenuEntry.Submenu submenu:
                    foreach (var child in CommandsIn(submenu.Entries))
                    {
                        yield return child;
                    }
                    break;
            }
        }
    }

    private static AppMenuEntry.Command App(string identifier, string title, string action, string key = "", AvivKeyModifiers modifiers = AvivKeyModifiers.None)
    {
        return new(new AppCommandSpec(identifier, title, action, key, modifiers, AppCommandRoute.Application));
    }

    private static AppMenuEntry.Command ViewModel(string identifier, string title, string action, string key = "", AvivKeyModifiers modifiers = AvivKeyModifiers.Ctrl)
    {
        return new(new AppCommandSpec(identifier, title, action, key, key.Length == 0 ? AvivKeyModifiers.None : modifiers, AppCommandRoute.AppViewModel));
    }

    private static AppMenuEntry.Command Editor(string identifier, string title, string action, string key = "", AvivKeyModifiers modifiers = AvivKeyModifiers.Ctrl)
    {
        return new(new AppCommandSpec(identifier, title, action, key, key.Length == 0 ? AvivKeyModifiers.None : modifiers, AppCommandRoute.Editor));
    }

    private static AppMenuEntry.Separator Sep() => new();

    private static AppMenuEntry.Submenu Submenu(string title, IReadOnlyList<AppMenuEntry> entries) => new(title, entries);
}
