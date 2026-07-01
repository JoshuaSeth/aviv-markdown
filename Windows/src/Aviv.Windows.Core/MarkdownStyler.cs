using System.Text.RegularExpressions;

namespace Aviv.Windows.Core;

public enum MarkdownStyleRole
{
    Base,
    Heading,
    SyntaxHidden,
    SyntaxVisible,
    InlineCode,
    CodeBlock,
    LinkText,
    Bold,
    Italic,
    Strikethrough,
    List,
    Quote,
    HorizontalRule,
    TaskMarkerChecked,
    TaskMarkerUnchecked,
    ImageSource,
    Table,
    TableSeparatorHidden
}

public sealed record MarkdownStyleRun(TextRange Range, MarkdownStyleRole Role, string? Detail = null);

public sealed record MarkdownStyleSnapshot(
    string Markdown,
    IReadOnlyList<MarkdownStyleRun> Runs,
    IReadOnlyList<MarkdownAnnotationToken> Annotations);

public sealed class MarkdownStyler
{
    public MarkdownStyleSnapshot Snapshot(string markdown, IReadOnlyList<TextRange>? selectedRanges = null)
    {
        var selected = selectedRanges ?? [];
        var runs = new List<MarkdownStyleRun>();
        if (markdown.Length == 0)
        {
            return new MarkdownStyleSnapshot(markdown, runs, []);
        }

        runs.Add(new MarkdownStyleRun(new TextRange(0, markdown.Length), MarkdownStyleRole.Base));
        ApplyBlockAndInlineStyles(markdown, selected, runs);
        return new MarkdownStyleSnapshot(markdown, runs.OrderBy(run => run.Range.Start).ThenBy(run => run.Range.Length).ToArray(), MarkdownAnnotationParser.Tokens(markdown, selected));
    }

    public IReadOnlyList<MarkdownStyleRun> RunsFor(string markdown, IReadOnlyList<TextRange>? selectedRanges = null)
    {
        return Snapshot(markdown, selectedRanges).Runs;
    }

    private static void ApplyBlockAndInlineStyles(string markdown, IReadOnlyList<TextRange> selectedRanges, List<MarkdownStyleRun> runs)
    {
        var tableRows = MarkdownTableParser.RowMap(markdown);
        var insideFence = false;

        foreach (var line in MarkdownDocument.Lines(markdown))
        {
            var trimmed = line.Text.Trim();
            var active = MarkdownDocument.IsLineActive(line.LineRange, selectedRanges, markdown.Length);

            if (IsFence(trimmed))
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.CodeBlock));
                runs.Add(new MarkdownStyleRun(line.ContentRange, active ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
                insideFence = !insideFence;
                continue;
            }

            if (insideFence)
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.CodeBlock));
                continue;
            }

            if (tableRows.TryGetValue(line.ContentRange.Start, out var tableRow))
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.Table));
                if (!active)
                {
                    runs.Add(new MarkdownStyleRun(line.ContentRange, tableRow.IsSeparator ? MarkdownStyleRole.TableSeparatorHidden : MarkdownStyleRole.SyntaxHidden));
                }
                else if (!tableRow.IsSeparator)
                {
                    ApplyInlineStyles(markdown, line.ContentRange, active, runs, renderImages: false);
                }
                continue;
            }

            if (ParseHeading(line.Text, line.ContentRange) is { } heading)
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.Heading, heading.Level.ToString()));
                runs.Add(new MarkdownStyleRun(heading.SyntaxRange, active ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
                ApplyInlineStyles(markdown, heading.BodyRange, active, runs);
            }
            else if (IsHorizontalRule(trimmed))
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.HorizontalRule));
            }
            else if (ParseTaskList(line.Text, line.ContentRange) is { } task)
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.List));
                runs.Add(new MarkdownStyleRun(task.PrefixRange, active ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
                runs.Add(new MarkdownStyleRun(task.CheckboxRange, task.Checked ? MarkdownStyleRole.TaskMarkerChecked : MarkdownStyleRole.TaskMarkerUnchecked));
                ApplyInlineStyles(markdown, task.BodyRange, active, runs);
            }
            else if (ParseList(line.Text, line.ContentRange) is { } list)
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.List));
                runs.Add(new MarkdownStyleRun(list.SyntaxRange, MarkdownStyleRole.SyntaxVisible));
                ApplyInlineStyles(markdown, list.BodyRange, active, runs);
            }
            else if (ParseBlockquote(line.Text, line.ContentRange) is { } quote)
            {
                runs.Add(new MarkdownStyleRun(line.LineRange, MarkdownStyleRole.Quote));
                runs.Add(new MarkdownStyleRun(quote.SyntaxRange, MarkdownStyleRole.SyntaxVisible));
                ApplyInlineStyles(markdown, quote.BodyRange, active, runs);
            }
            else
            {
                ApplyInlineStyles(markdown, line.ContentRange, active, runs);
            }
        }
    }

    private static void ApplyInlineStyles(string markdown, TextRange searchRange, bool lineActive, List<MarkdownStyleRun> runs, bool renderImages = true)
    {
        if (searchRange.Length == 0)
        {
            return;
        }

        var protectedRanges = new List<TextRange>();

        if (renderImages)
        {
            ApplyMatches(MarkdownPatterns.ImageRegex, markdown, searchRange, protectedRanges, match =>
            {
                var range = new TextRange(match.Index, match.Length);
                runs.Add(new MarkdownStyleRun(range, MarkdownStyleRole.ImageSource));
                protectedRanges.Add(range);
            });
        }

        ApplyMatches(new Regex(@"`([^`\n]+)`"), markdown, searchRange, protectedRanges, match =>
        {
            var content = new TextRange(match.Groups[1].Index, match.Groups[1].Length);
            runs.Add(new MarkdownStyleRun(new TextRange(match.Index, 1), lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
            runs.Add(new MarkdownStyleRun(new TextRange(match.Index + match.Length - 1, 1), lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
            runs.Add(new MarkdownStyleRun(content, MarkdownStyleRole.InlineCode));
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        ApplyMatches(MarkdownPatterns.LinkRegex, markdown, searchRange, protectedRanges, match =>
        {
            var textRange = new TextRange(match.Groups[1].Index, match.Groups[1].Length);
            var targetRange = new TextRange(match.Groups[2].Index, match.Groups[2].Length);
            runs.Add(new MarkdownStyleRun(textRange, MarkdownStyleRole.LinkText));
            runs.Add(new MarkdownStyleRun(new TextRange(match.Index, textRange.Start - match.Index), lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
            runs.Add(new MarkdownStyleRun(new TextRange(textRange.End, targetRange.Start - textRange.End), lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
            runs.Add(new MarkdownStyleRun(targetRange, lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
            runs.Add(new MarkdownStyleRun(new TextRange(targetRange.End, match.Index + match.Length - targetRange.End), lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden));
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        ApplyDelimiterStyle(new Regex(@"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"), MarkdownStyleRole.Bold, markdown, searchRange, lineActive, protectedRanges, runs);
        ApplyDelimiterStyle(new Regex(@"(~~)(?=\S)(.+?)(?<=\S)~~"), MarkdownStyleRole.Strikethrough, markdown, searchRange, lineActive, protectedRanges, runs);
        ApplySingleDelimiterStyle(new Regex(@"(?<!\*)\*(?!\s|\*)([^*\n]+?)(?<!\s)\*(?!\*)"), MarkdownStyleRole.Italic, "*", markdown, searchRange, lineActive, protectedRanges, runs);
        ApplySingleDelimiterStyle(new Regex(@"(?<!\w)_(?!\s|_)([^_\n]+?)(?<!\s)_(?!\w)"), MarkdownStyleRole.Italic, "_", markdown, searchRange, lineActive, protectedRanges, runs);
    }

    private static void ApplyDelimiterStyle(
        Regex regex,
        MarkdownStyleRole contentRole,
        string markdown,
        TextRange searchRange,
        bool lineActive,
        List<TextRange> protectedRanges,
        List<MarkdownStyleRun> runs)
    {
        ApplyMatches(regex, markdown, searchRange, protectedRanges, match =>
        {
            var delimiter = new TextRange(match.Groups[1].Index, match.Groups[1].Length);
            var content = new TextRange(match.Groups[2].Index, match.Groups[2].Length);
            var syntaxRole = lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden;
            runs.Add(new MarkdownStyleRun(delimiter, syntaxRole));
            runs.Add(new MarkdownStyleRun(new TextRange(content.End, delimiter.Length), syntaxRole));
            runs.Add(new MarkdownStyleRun(content, contentRole));
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });
    }

    private static void ApplySingleDelimiterStyle(
        Regex regex,
        MarkdownStyleRole contentRole,
        string delimiter,
        string markdown,
        TextRange searchRange,
        bool lineActive,
        List<TextRange> protectedRanges,
        List<MarkdownStyleRun> runs)
    {
        ApplyMatches(regex, markdown, searchRange, protectedRanges, match =>
        {
            var content = new TextRange(match.Groups[1].Index, match.Groups[1].Length);
            var syntaxRole = lineActive ? MarkdownStyleRole.SyntaxVisible : MarkdownStyleRole.SyntaxHidden;
            runs.Add(new MarkdownStyleRun(new TextRange(match.Index, delimiter.Length), syntaxRole));
            runs.Add(new MarkdownStyleRun(new TextRange(match.Index + match.Length - delimiter.Length, delimiter.Length), syntaxRole));
            runs.Add(new MarkdownStyleRun(content, contentRole));
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });
    }

    private static void ApplyMatches(
        Regex regex,
        string markdown,
        TextRange searchRange,
        IReadOnlyList<TextRange> protectedRanges,
        Action<System.Text.RegularExpressions.Match> handler)
    {
        foreach (System.Text.RegularExpressions.Match match in regex.Matches(markdown))
        {
            var range = new TextRange(match.Index, match.Length);
            if (!searchRange.Intersects(range))
            {
                continue;
            }

            if (protectedRanges.Any(protectedRange => protectedRange.Intersects(range)))
            {
                continue;
            }

            handler(match);
        }
    }

    private sealed record HeadingParse(int Level, TextRange SyntaxRange, TextRange BodyRange);
    private sealed record BodyParse(TextRange SyntaxRange, TextRange BodyRange);
    private sealed record TaskParse(TextRange PrefixRange, TextRange CheckboxRange, TextRange BodyRange, bool Checked);

    private static HeadingParse? ParseHeading(string line, TextRange contentRange)
    {
        var match = Regex.Match(line, @"^(#{1,6})\s+");
        if (!match.Success)
        {
            return null;
        }

        var syntax = new TextRange(contentRange.Start + match.Index, match.Length);
        var body = new TextRange(syntax.End, contentRange.End - syntax.End);
        return new HeadingParse(match.Groups[1].Length, syntax, body);
    }

    private static BodyParse? ParseList(string line, TextRange contentRange)
    {
        var match = Regex.Match(line, @"^(\s*(?:[-*+]|\d+[.)])\s+)");
        if (!match.Success)
        {
            return null;
        }

        var syntax = new TextRange(contentRange.Start + match.Index, match.Length);
        return new BodyParse(syntax, new TextRange(syntax.End, contentRange.End - syntax.End));
    }

    private static TaskParse? ParseTaskList(string line, TextRange contentRange)
    {
        var match = Regex.Match(line, @"^(\s*(?:[-*+]|\d+[.)])\s+)(\[[ xX]\])\s+");
        if (!match.Success)
        {
            return null;
        }

        var prefix = new TextRange(contentRange.Start + match.Groups[1].Index, match.Groups[1].Length);
        var checkbox = new TextRange(contentRange.Start + match.Groups[2].Index, match.Groups[2].Length);
        var markerEnd = contentRange.Start + match.Index + match.Length;
        return new TaskParse(
            new TextRange(contentRange.Start + match.Index, match.Length),
            checkbox,
            new TextRange(markerEnd, contentRange.End - markerEnd),
            match.Groups[2].Value.Contains('x') || match.Groups[2].Value.Contains('X'));
    }

    private static BodyParse? ParseBlockquote(string line, TextRange contentRange)
    {
        var match = Regex.Match(line, @"^(\s*>\s?)");
        if (!match.Success)
        {
            return null;
        }

        var syntax = new TextRange(contentRange.Start + match.Index, match.Length);
        return new BodyParse(syntax, new TextRange(syntax.End, contentRange.End - syntax.End));
    }

    private static bool IsHorizontalRule(string trimmed)
    {
        var compact = new string(trimmed.Where(character => character is not (' ' or '\t')).ToArray());
        return compact.Length >= 3 && compact.All(character => character == compact[0]) && compact[0] is '-' or '_' or '*';
    }

    private static bool IsFence(string trimmedLine)
    {
        return trimmedLine.StartsWith("```", StringComparison.Ordinal) || trimmedLine.StartsWith("~~~", StringComparison.Ordinal);
    }
}
