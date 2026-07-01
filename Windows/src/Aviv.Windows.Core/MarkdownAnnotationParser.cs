using System.Text.RegularExpressions;

namespace Aviv.Windows.Core;

public enum MarkdownAnnotationRole
{
    Heading,
    InlineDelimiter,
    LinkSource,
    LinkTarget,
    CodeFence
}

public sealed record MarkdownAnnotationToken(TextRange Range, string Label, MarkdownAnnotationRole Role);

public static class MarkdownAnnotationParser
{
    public static IReadOnlyList<MarkdownAnnotationToken> Tokens(string markdown, IReadOnlyList<TextRange> selectedRanges)
    {
        if (markdown.Length == 0 || selectedRanges.Count == 0)
        {
            return [];
        }

        var output = new List<MarkdownAnnotationToken>();
        var visitedLineStarts = new HashSet<int>();

        foreach (var selection in selectedRanges)
        {
            var target = selection.Length == 0
                ? new TextRange(Math.Clamp(selection.Start, 0, Math.Max(0, markdown.Length - 1)), 0)
                : selection;
            var line = MarkdownDocument.LineContaining(markdown, target.Start);
            if (!visitedLineStarts.Add(line.LineRange.Start))
            {
                continue;
            }

            var focused = selectedRanges
                .Select(range => range.Length == 0
                    ? new TextRange(Math.Clamp(range.Start, 0, Math.Max(0, markdown.Length - 1)) - line.ContentRange.Start, 0)
                    : range.Intersection(line.ContentRange)?.OffsetBy(-line.ContentRange.Start))
                .Where(range => range is not null)
                .Select(range => range!.Value)
                .ToArray();

            output.AddRange(TokensInLine(line.Text, line.ContentRange, focused));
        }

        return output
            .OrderBy(token => token.Range.Start)
            .ThenBy(token => token.Range.Length)
            .ToArray();
    }

    private static IReadOnlyList<MarkdownAnnotationToken> TokensInLine(string line, TextRange contentRange, IReadOnlyList<TextRange> focusedRanges)
    {
        var tokens = new List<MarkdownAnnotationToken>();
        var protectedRanges = new List<TextRange>();

        var heading = Regex.Match(line, @"^(#{1,6})\s+");
        if (heading.Success)
        {
            var marker = heading.Groups[1];
            tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + marker.Index, marker.Length), marker.Value, MarkdownAnnotationRole.Heading));
        }

        var fence = Regex.Match(line, @"^\s*(```|~~~).*$");
        if (fence.Success)
        {
            tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + fence.Index, fence.Length), fence.Value, MarkdownAnnotationRole.CodeFence));
        }

        Collect(line, new Regex(@"`([^`\n]+)`"), protectedRanges, match =>
        {
            if (ShouldReveal(new TextRange(match.Index, match.Length), focusedRanges))
            {
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index, 1), "`", MarkdownAnnotationRole.InlineDelimiter));
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index + match.Length - 1, 1), "`", MarkdownAnnotationRole.InlineDelimiter));
            }
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        Collect(line, MarkdownPatterns.ImageRegex, protectedRanges, match =>
        {
            if (ShouldReveal(new TextRange(match.Index, match.Length), focusedRanges))
            {
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index, match.Length), match.Value, MarkdownAnnotationRole.LinkSource));
            }
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        Collect(line, MarkdownPatterns.LinkRegex, protectedRanges, match =>
        {
            if (ShouldReveal(new TextRange(match.Index, match.Length), focusedRanges))
            {
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index, match.Length), match.Value, MarkdownAnnotationRole.LinkSource));
            }
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        Collect(line, new Regex(@"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"), protectedRanges, match =>
        {
            if (ShouldReveal(new TextRange(match.Index, match.Length), focusedRanges))
            {
                var delimiter = match.Groups[1];
                var content = match.Groups[2];
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + delimiter.Index, delimiter.Length), delimiter.Value, MarkdownAnnotationRole.InlineDelimiter));
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + content.Index + content.Length, delimiter.Length), delimiter.Value, MarkdownAnnotationRole.InlineDelimiter));
            }
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        Collect(line, new Regex(@"(~~)(?=\S)(.+?)(?<=\S)~~"), protectedRanges, match =>
        {
            if (ShouldReveal(new TextRange(match.Index, match.Length), focusedRanges))
            {
                var delimiter = match.Groups[1];
                var content = match.Groups[2];
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + delimiter.Index, delimiter.Length), "~~", MarkdownAnnotationRole.InlineDelimiter));
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + content.Index + content.Length, delimiter.Length), "~~", MarkdownAnnotationRole.InlineDelimiter));
            }
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        Collect(line, new Regex(@"(?<!\*)\*(?!\s|\*)([^*\n]+?)(?<!\s)\*(?!\*)"), protectedRanges, match =>
        {
            if (ShouldReveal(new TextRange(match.Index, match.Length), focusedRanges))
            {
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index, 1), "*", MarkdownAnnotationRole.InlineDelimiter));
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index + match.Length - 1, 1), "*", MarkdownAnnotationRole.InlineDelimiter));
            }
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        Collect(line, new Regex(@"(?<!\w)_(?!\s|_)([^_\n]+?)(?<!\s)_(?!\w)"), protectedRanges, match =>
        {
            if (ShouldReveal(new TextRange(match.Index, match.Length), focusedRanges))
            {
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index, 1), "_", MarkdownAnnotationRole.InlineDelimiter));
                tokens.Add(new MarkdownAnnotationToken(new TextRange(contentRange.Start + match.Index + match.Length - 1, 1), "_", MarkdownAnnotationRole.InlineDelimiter));
            }
            protectedRanges.Add(new TextRange(match.Index, match.Length));
        });

        return tokens;
    }

    private static void Collect(string line, Regex regex, IReadOnlyList<TextRange> protectedRanges, Action<Match> handler)
    {
        foreach (Match match in regex.Matches(line))
        {
            var range = new TextRange(match.Index, match.Length);
            if (protectedRanges.Any(protectedRange => protectedRange.Intersects(range)))
            {
                continue;
            }

            handler(match);
        }
    }

    private static bool ShouldReveal(TextRange matchRange, IReadOnlyList<TextRange> focusedRanges)
    {
        return focusedRanges.Any(focused =>
            focused.Length == 0
                ? matchRange.Contains(focused.Start, includeEnd: true)
                : matchRange.Intersects(focused));
    }
}
