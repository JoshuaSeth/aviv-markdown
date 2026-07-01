namespace Aviv.Windows.Core;

public readonly record struct MarkdownLine(TextRange LineRange, TextRange ContentRange, string Text);

public static class MarkdownDocument
{
    public static IReadOnlyList<MarkdownLine> Lines(string markdown)
    {
        if (markdown.Length == 0)
        {
            return [new MarkdownLine(TextRange.Empty, TextRange.Empty, string.Empty)];
        }

        var lines = new List<MarkdownLine>();
        var index = 0;

        while (index < markdown.Length)
        {
            var newlineIndex = markdown.IndexOf('\n', index);
            var lineEnd = newlineIndex < 0 ? markdown.Length : newlineIndex + 1;
            var contentEnd = lineEnd;

            while (contentEnd > index && (markdown[contentEnd - 1] == '\n' || markdown[contentEnd - 1] == '\r'))
            {
                contentEnd--;
            }

            var lineRange = new TextRange(index, lineEnd - index);
            var contentRange = new TextRange(index, contentEnd - index);
            lines.Add(new MarkdownLine(lineRange, contentRange, markdown.Substring(contentRange.Start, contentRange.Length)));
            index = lineEnd;
        }

        return lines;
    }

    public static MarkdownLine LineContaining(string markdown, int location)
    {
        if (markdown.Length == 0)
        {
            return new MarkdownLine(TextRange.Empty, TextRange.Empty, string.Empty);
        }

        var safeLocation = Math.Clamp(location, 0, markdown.Length - 1);
        foreach (var line in Lines(markdown))
        {
            if (line.LineRange.Contains(safeLocation) || safeLocation == line.LineRange.End)
            {
                return line;
            }
        }

        return Lines(markdown).Last();
    }

    public static bool IsLineActive(TextRange lineRange, IReadOnlyList<TextRange> selectedRanges, int documentLength)
    {
        if (selectedRanges.Count == 0)
        {
            return false;
        }

        foreach (var selection in selectedRanges)
        {
            var clamped = selection.Length == 0
                ? new TextRange(Math.Clamp(selection.Start, 0, Math.Max(0, documentLength - 1)), 0)
                : selection;
            if (lineRange.Intersects(clamped) || lineRange.Contains(clamped.Start, includeEnd: true))
            {
                return true;
            }
        }

        return false;
    }
}
