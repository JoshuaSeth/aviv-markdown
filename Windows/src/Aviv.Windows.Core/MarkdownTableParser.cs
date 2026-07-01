namespace Aviv.Windows.Core;

public sealed record MarkdownTableCell(TextRange SourceRange, TextRange ContentRange, string Text);

public sealed record MarkdownTableRow(
    TextRange LineRange,
    TextRange ContentRange,
    IReadOnlyList<MarkdownTableCell> Cells,
    bool IsHeader,
    bool IsSeparator);

public sealed record MarkdownTableBlock(IReadOnlyList<MarkdownTableRow> Rows)
{
    public TextRange Range
    {
        get
        {
            if (Rows.Count == 0)
            {
                return TextRange.Empty;
            }

            var first = Rows[0];
            var last = Rows[^1];
            return new TextRange(first.LineRange.Start, last.LineRange.End - first.LineRange.Start);
        }
    }
}

public static class MarkdownTableParser
{
    public static IReadOnlyList<MarkdownTableBlock> Blocks(string markdown)
    {
        if (markdown.Length == 0)
        {
            return [];
        }

        var lines = MarkdownDocument.Lines(markdown);
        var blocks = new List<MarkdownTableBlock>();
        var index = 0;
        var insideFence = false;

        while (index < lines.Count)
        {
            var line = lines[index];
            var trimmed = line.Text.Trim();

            if (IsFence(trimmed))
            {
                insideFence = !insideFence;
                index++;
                continue;
            }

            if (insideFence)
            {
                index++;
                continue;
            }

            if (index + 1 < lines.Count && IsPotentialTableLine(line.Text) && IsSeparatorLine(lines[index + 1].Text))
            {
                var rows = new List<MarkdownTableRow>
                {
                    RowFrom(line, markdown, isHeader: true, isSeparator: false),
                    RowFrom(lines[index + 1], markdown, isHeader: false, isSeparator: true)
                };
                index += 2;

                while (index < lines.Count)
                {
                    var candidate = lines[index];
                    if (!IsPotentialTableLine(candidate.Text) || candidate.Text.Trim().Length == 0)
                    {
                        break;
                    }

                    rows.Add(RowFrom(candidate, markdown, isHeader: false, isSeparator: false));
                    index++;
                }

                if (rows.Any(row => !row.IsSeparator && row.Cells.Count > 0))
                {
                    blocks.Add(new MarkdownTableBlock(rows));
                }

                continue;
            }

            index++;
        }

        return blocks;
    }

    public static IReadOnlyDictionary<int, MarkdownTableRow> RowMap(string markdown)
    {
        return Blocks(markdown)
            .SelectMany(block => block.Rows)
            .ToDictionary(row => row.ContentRange.Start, row => row);
    }

    public static MarkdownTableBlock? BlockContaining(int location, string markdown)
    {
        return Blocks(markdown).FirstOrDefault(block => block.Range.Contains(location, includeEnd: true));
    }

    private static MarkdownTableRow RowFrom(MarkdownLine line, string markdown, bool isHeader, bool isSeparator)
    {
        return new MarkdownTableRow(
            line.LineRange,
            line.ContentRange,
            ParseCells(markdown, line.ContentRange),
            isHeader,
            isSeparator);
    }

    private static IReadOnlyList<MarkdownTableCell> ParseCells(string markdown, TextRange contentRange)
    {
        if (contentRange.Length == 0)
        {
            return [];
        }

        var segments = new List<TextRange>();
        var segmentStart = contentRange.Start;
        var end = contentRange.End;

        for (var location = contentRange.Start; location < end; location++)
        {
            var isEscaped = location > contentRange.Start && markdown[location - 1] == '\\';
            if (markdown[location] == '|' && !isEscaped)
            {
                segments.Add(new TextRange(segmentStart, location - segmentStart));
                segmentStart = location + 1;
            }
        }

        segments.Add(new TextRange(segmentStart, end - segmentStart));

        if (segments.Count > 0 && markdown[contentRange.Start] == '|' && string.IsNullOrWhiteSpace(Substring(markdown, segments[0])))
        {
            segments.RemoveAt(0);
        }

        if (segments.Count > 0 && markdown[end - 1] == '|' && string.IsNullOrWhiteSpace(Substring(markdown, segments[^1])))
        {
            segments.RemoveAt(segments.Count - 1);
        }

        return segments.Select(segment =>
        {
            var content = TrimmedRange(markdown, segment);
            return new MarkdownTableCell(segment, content, Substring(markdown, content));
        }).ToArray();
    }

    private static bool IsPotentialTableLine(string line)
    {
        return line.Contains('|') && line.Split('|').Length >= 2;
    }

    private static bool IsSeparatorLine(string line)
    {
        if (!IsPotentialTableLine(line))
        {
            return false;
        }

        var parts = line.Split('|')
            .Select(part => part.Trim())
            .Where(part => part.Length > 0)
            .ToArray();
        if (parts.Length == 0)
        {
            return false;
        }

        return parts.All(part =>
        {
            if (part.Length < 3)
            {
                return false;
            }

            var trimmed = part.Trim(':');
            return trimmed.Length > 0 && trimmed.All(character => character == '-');
        });
    }

    private static bool IsFence(string trimmedLine)
    {
        return trimmedLine.StartsWith("```", StringComparison.Ordinal) || trimmedLine.StartsWith("~~~", StringComparison.Ordinal);
    }

    private static TextRange TrimmedRange(string markdown, TextRange range)
    {
        var start = range.Start;
        var end = range.End;

        while (start < end && (markdown[start] == ' ' || markdown[start] == '\t'))
        {
            start++;
        }

        while (end > start && (markdown[end - 1] == ' ' || markdown[end - 1] == '\t'))
        {
            end--;
        }

        return new TextRange(start, end - start);
    }

    private static string Substring(string markdown, TextRange range)
    {
        return markdown.Substring(range.Start, range.Length);
    }
}
