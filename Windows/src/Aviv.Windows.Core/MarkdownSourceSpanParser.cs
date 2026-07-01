namespace Aviv.Windows.Core;

public enum MarkdownEditableSourceKind
{
    Image,
    Link
}

public sealed record MarkdownEditableSourceSpan(TextRange Range, string Source, MarkdownEditableSourceKind Kind);

public static class MarkdownSourceSpanParser
{
    public static MarkdownEditableSourceSpan? EditableSpanContaining(int location, string markdown)
    {
        return ImageSpanContaining(location, markdown) ?? LinkSpanContaining(location, markdown);
    }

    public static MarkdownEditableSourceSpan? ImageSpanContaining(int location, string markdown)
    {
        return SourceSpanContaining(location, markdown, MarkdownPatterns.ImageRegex, MarkdownEditableSourceKind.Image);
    }

    public static MarkdownEditableSourceSpan? LinkSpanContaining(int location, string markdown)
    {
        return SourceSpanContaining(location, markdown, MarkdownPatterns.LinkRegex, MarkdownEditableSourceKind.Link);
    }

    private static MarkdownEditableSourceSpan? SourceSpanContaining(
        int location,
        string markdown,
        System.Text.RegularExpressions.Regex regex,
        MarkdownEditableSourceKind kind)
    {
        if (markdown.Length == 0)
        {
            return null;
        }

        var line = MarkdownDocument.LineContaining(markdown, location);
        foreach (System.Text.RegularExpressions.Match match in regex.Matches(line.Text))
        {
            var range = new TextRange(line.ContentRange.Start + match.Index, match.Length);
            if (range.Contains(location, includeEnd: true))
            {
                return new MarkdownEditableSourceSpan(range, markdown.Substring(range.Start, range.Length), kind);
            }
        }

        return null;
    }
}
