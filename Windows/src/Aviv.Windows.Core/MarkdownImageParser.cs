namespace Aviv.Windows.Core;

public sealed record MarkdownImageReference(
    TextRange Range,
    TextRange AltRange,
    TextRange TargetRange,
    string AltText,
    string Target,
    string Source);

public static class MarkdownImageParser
{
    public static IReadOnlyList<MarkdownImageReference> Images(string markdown, TextRange? searchRange = null)
    {
        if (markdown.Length == 0)
        {
            return [];
        }

        var range = searchRange ?? new TextRange(0, markdown.Length);
        var matches = MarkdownPatterns.ImageRegex.Matches(markdown);
        return matches
            .Where(match => match.Success && match.Groups.Count >= 3 && new TextRange(match.Index, match.Length).Intersects(range))
            .Select(match =>
            {
                var altRange = new TextRange(match.Groups[1].Index, match.Groups[1].Length);
                var targetRange = new TextRange(match.Groups[2].Index, match.Groups[2].Length);
                var sourceRange = new TextRange(match.Index, match.Length);
                return new MarkdownImageReference(
                    sourceRange,
                    altRange,
                    targetRange,
                    markdown.Substring(altRange.Start, altRange.Length),
                    markdown.Substring(targetRange.Start, targetRange.Length),
                    markdown.Substring(sourceRange.Start, sourceRange.Length));
            })
            .ToArray();
    }
}

public static class MarkdownImageResolver
{
    public static Uri? FileUriFor(string rawTarget, Uri? baseUri = null)
    {
        var target = CleanTarget(rawTarget);
        if (target.Length == 0 || target.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || target.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (target.StartsWith("file://", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(target, UriKind.Absolute, out var fileUri))
        {
            return fileUri;
        }

        if (target == "~" || target.StartsWith("~/", StringComparison.Ordinal))
        {
            target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), target.Length == 1 ? string.Empty : target[2..]);
        }

        if (Path.IsPathRooted(target))
        {
            return new Uri(Path.GetFullPath(target));
        }

        if (baseUri is { IsFile: true })
        {
            return new Uri(Path.GetFullPath(Path.Combine(baseUri.LocalPath, target)));
        }

        return new Uri(Path.GetFullPath(target));
    }

    private static string CleanTarget(string rawTarget)
    {
        var target = rawTarget.Trim();
        if (target.StartsWith('<') && target.EndsWith('>') && target.Length >= 2)
        {
            target = target[1..^1];
        }

        return Uri.UnescapeDataString(target);
    }
}
