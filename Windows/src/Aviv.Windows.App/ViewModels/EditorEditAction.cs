namespace Aviv.Windows.App.ViewModels;

public enum EditorEditActionKind
{
    Wrap,
    Heading
}

public sealed record EditorEditAction(EditorEditActionKind Kind, string Prefix = "", string Suffix = "", int HeadingLevel = 1)
{
    public static EditorEditAction Wrap(string prefix, string suffix) => new(EditorEditActionKind.Wrap, prefix, suffix);
    public static EditorEditAction Heading(int level) => new(EditorEditActionKind.Heading, HeadingLevel: level);
}

public enum EditorCommandKind
{
    Undo,
    Redo,
    Cut,
    Copy,
    Paste,
    PastePlainText,
    SelectAll,
    Find,
    FindAndReplace,
    FindNext,
    FindPrevious
}
