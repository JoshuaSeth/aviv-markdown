namespace Aviv.Windows.Core;

public sealed record MarkdownMinimapKind(string Name, int Level = 0, int Depth = 0, bool Checked = false, int Columns = 0)
{
    public static MarkdownMinimapKind Blank { get; } = new("blank");
    public static MarkdownMinimapKind Body { get; } = new("body");
    public static MarkdownMinimapKind Quote { get; } = new("quote");
    public static MarkdownMinimapKind CodeFence { get; } = new("codeFence");
    public static MarkdownMinimapKind Code { get; } = new("code");
    public static MarkdownMinimapKind ThematicBreak { get; } = new("thematicBreak");

    public static MarkdownMinimapKind Heading(int level) => new("heading", Level: level);
    public static MarkdownMinimapKind UnorderedList(int depth) => new("unorderedList", Depth: depth);
    public static MarkdownMinimapKind OrderedList(int depth) => new("orderedList", Depth: depth);
    public static MarkdownMinimapKind TaskList(bool isChecked, int depth) => new("taskList", Depth: depth, Checked: isChecked);
    public static MarkdownMinimapKind TableHeader(int columns) => new("tableHeader", Columns: columns);
    public static MarkdownMinimapKind TableSeparator(int columns) => new("tableSeparator", Columns: columns);
    public static MarkdownMinimapKind TableRow(int columns) => new("tableRow", Columns: columns);
}

public sealed record MarkdownMinimapLine(MarkdownMinimapKind Kind, int QuoteDepth, int TextLength);

public static class MarkdownMinimapStructure
{
    public static IReadOnlyList<MarkdownMinimapLine> Lines(string markdown)
    {
        var documentLines = MarkdownDocument.Lines(markdown);
        var tableRows = MarkdownTableParser.RowMap(markdown);
        var result = new List<MarkdownMinimapLine>();
        var insideFence = false;

        foreach (var line in documentLines)
        {
            var stripped = StripQuoteMarkers(line.Text);
            var trimmed = stripped.Content.Trim();
            var textLength = trimmed.Length;

            if (IsFence(trimmed))
            {
                result.Add(new MarkdownMinimapLine(MarkdownMinimapKind.CodeFence, stripped.QuoteDepth, textLength));
                insideFence = !insideFence;
                continue;
            }

            if (insideFence)
            {
                result.Add(new MarkdownMinimapLine(MarkdownMinimapKind.Code, stripped.QuoteDepth, textLength));
                continue;
            }

            if (trimmed.Length == 0)
            {
                result.Add(new MarkdownMinimapLine(MarkdownMinimapKind.Blank, stripped.QuoteDepth, 0));
                continue;
            }

            if (stripped.QuoteDepth == 0 && tableRows.TryGetValue(line.ContentRange.Start, out var tableRow))
            {
                result.Add(new MarkdownMinimapLine(TableKind(tableRow), 0, textLength));
                continue;
            }

            if (HeadingLevel(trimmed) is { } level)
            {
                result.Add(new MarkdownMinimapLine(MarkdownMinimapKind.Heading(level), stripped.QuoteDepth, textLength));
                continue;
            }

            if (ListKind(stripped.Content) is { } listKind)
            {
                result.Add(new MarkdownMinimapLine(listKind, stripped.QuoteDepth, textLength));
                continue;
            }

            if (IsThematicBreak(trimmed))
            {
                result.Add(new MarkdownMinimapLine(MarkdownMinimapKind.ThematicBreak, stripped.QuoteDepth, textLength));
                continue;
            }

            result.Add(new MarkdownMinimapLine(stripped.QuoteDepth > 0 ? MarkdownMinimapKind.Quote : MarkdownMinimapKind.Body, stripped.QuoteDepth, textLength));
        }

        return result;
    }

    private static MarkdownMinimapKind TableKind(MarkdownTableRow row)
    {
        var columns = Math.Max(1, row.Cells.Count);
        if (row.IsHeader)
        {
            return MarkdownMinimapKind.TableHeader(columns);
        }

        return row.IsSeparator ? MarkdownMinimapKind.TableSeparator(columns) : MarkdownMinimapKind.TableRow(columns);
    }

    private static (string Content, int QuoteDepth) StripQuoteMarkers(string line)
    {
        var content = line;
        var quoteDepth = 0;

        while (true)
        {
            var candidate = content.TrimStart(' ', '\t');
            if (!candidate.StartsWith('>'))
            {
                break;
            }

            quoteDepth++;
            content = candidate[1..];
            if (content.StartsWith(' ') || content.StartsWith('\t'))
            {
                content = content[1..];
            }
        }

        return (content, quoteDepth);
    }

    private static int? HeadingLevel(string trimmed)
    {
        var level = 0;
        while (level < trimmed.Length && trimmed[level] == '#')
        {
            level++;
        }

        if (level is < 1 or > 6)
        {
            return null;
        }

        return level == trimmed.Length || trimmed[level] is ' ' or '\t' ? level : null;
    }

    private static MarkdownMinimapKind? ListKind(string content)
    {
        var leadingWhitespace = content.TakeWhile(character => character is ' ' or '\t');
        var depth = Math.Min(5, leadingWhitespace.Sum(character => character == '\t' ? 2 : 1) / 2);
        var trimmed = content.Trim();

        if (UnorderedListBody(trimmed) is { } unorderedBody)
        {
            return TaskState(unorderedBody) is { } isChecked
                ? MarkdownMinimapKind.TaskList(isChecked, depth)
                : MarkdownMinimapKind.UnorderedList(depth);
        }

        if (OrderedListBody(trimmed) is { } orderedBody)
        {
            return TaskState(orderedBody) is { } isChecked
                ? MarkdownMinimapKind.TaskList(isChecked, depth)
                : MarkdownMinimapKind.OrderedList(depth);
        }

        return null;
    }

    private static string? UnorderedListBody(string trimmed)
    {
        if (trimmed.Length < 2 || trimmed[0] is not ('-' or '*' or '+') || trimmed[1] is not (' ' or '\t'))
        {
            return null;
        }

        return trimmed[2..];
    }

    private static string? OrderedListBody(string trimmed)
    {
        var digitCount = 0;
        while (digitCount < trimmed.Length && char.IsDigit(trimmed[digitCount]))
        {
            digitCount++;
        }

        if (digitCount == 0 || digitCount >= trimmed.Length || trimmed[digitCount] is not ('.' or ')'))
        {
            return null;
        }

        var markerEnd = digitCount + 1;
        if (markerEnd >= trimmed.Length || trimmed[markerEnd] is not (' ' or '\t'))
        {
            return null;
        }

        return trimmed[(markerEnd + 1)..];
    }

    private static bool? TaskState(string body)
    {
        var trimmed = body.Trim();
        if (trimmed.Length < 3 || trimmed[0] != '[' || trimmed[2] != ']')
        {
            return null;
        }

        return trimmed[1] switch
        {
            'x' or 'X' => true,
            ' ' => false,
            _ => null
        };
    }

    private static bool IsThematicBreak(string trimmed)
    {
        var compact = new string(trimmed.Where(character => character is not (' ' or '\t')).ToArray());
        return compact.Length >= 3 && compact.All(character => character == compact[0]) && compact[0] is '-' or '_' or '*';
    }

    private static bool IsFence(string trimmedLine)
    {
        return trimmedLine.StartsWith("```", StringComparison.Ordinal) || trimmedLine.StartsWith("~~~", StringComparison.Ordinal);
    }
}
