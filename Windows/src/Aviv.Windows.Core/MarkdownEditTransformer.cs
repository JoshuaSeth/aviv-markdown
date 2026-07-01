using System.Text.RegularExpressions;

namespace Aviv.Windows.Core;

public sealed record MarkdownEditResult(string Markdown, TextRange Selection);

public static class MarkdownEditTransformer
{
    public static MarkdownEditResult WrapSelection(string markdown, TextRange selection, string prefix, string suffix)
    {
        var start = Math.Clamp(selection.Start, 0, markdown.Length);
        var length = Math.Clamp(selection.Length, 0, markdown.Length - start);
        var safeSelection = new TextRange(start, length);

        if (safeSelection.Length > 0)
        {
            var selectedText = markdown.Substring(safeSelection.Start, safeSelection.Length);
            var replacement = prefix + selectedText + suffix;
            var next = markdown.Remove(safeSelection.Start, safeSelection.Length).Insert(safeSelection.Start, replacement);
            return new MarkdownEditResult(next, new TextRange(safeSelection.Start + prefix.Length, safeSelection.Length));
        }

        var inserted = prefix + suffix;
        var result = markdown.Insert(safeSelection.Start, inserted);
        return new MarkdownEditResult(result, new TextRange(safeSelection.Start + prefix.Length, 0));
    }

    public static MarkdownEditResult MakeHeading(string markdown, TextRange selection, int level)
    {
        var safeLevel = Math.Clamp(level, 1, 6);
        var hashes = new string('#', safeLevel) + " ";
        var line = MarkdownDocument.LineContaining(markdown, selection.Start);
        var source = markdown.Substring(line.ContentRange.Start, line.ContentRange.Length);
        var body = Regex.Replace(source, @"^#{1,6}\s+", string.Empty);
        var replacement = hashes + body;
        var next = markdown.Remove(line.ContentRange.Start, line.ContentRange.Length).Insert(line.ContentRange.Start, replacement);
        return new MarkdownEditResult(next, new TextRange(Math.Min(line.ContentRange.Start + hashes.Length, next.Length), 0));
    }
}
