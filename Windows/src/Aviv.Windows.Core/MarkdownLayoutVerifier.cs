namespace Aviv.Windows.Core;

public sealed record MarkdownLayoutVerificationResult(bool Passed, IReadOnlyList<string> Failures, int MeasuredSelections);

public static class MarkdownLayoutVerifier
{
    public static MarkdownLayoutVerificationResult Verify(string markdown)
    {
        var styler = new MarkdownStyler();
        var probes = MakeProbes(markdown);
        var cursorLocations = MakeCursorLocations(markdown);
        var failures = new List<string>();

        var baseline = ContentRolesForProbes(styler.Snapshot(markdown, [new TextRange(0, 0)]), probes);

        foreach (var location in cursorLocations)
        {
            var snapshot = styler.Snapshot(markdown, [new TextRange(location, 0)]);
            var current = ContentRolesForProbes(snapshot, probes);

            foreach (var probe in probes)
            {
                if (!baseline.TryGetValue(probe.Name, out var baselineRoles) || !current.TryGetValue(probe.Name, out var currentRoles))
                {
                    failures.Add($"Missing style measurement for {probe.Name} at cursor {location}.");
                    continue;
                }

                if (!baselineRoles.SequenceEqual(currentRoles))
                {
                    failures.Add($"Content style shifted for {probe.Name} at cursor {location}: {string.Join(",", baselineRoles)} -> {string.Join(",", currentRoles)}");
                }
            }
        }

        return new MarkdownLayoutVerificationResult(failures.Count == 0, failures, cursorLocations.Count);
    }

    private sealed record Probe(string Name, TextRange Range);

    private static IReadOnlyList<Probe> MakeProbes(string markdown)
    {
        string[] needles =
        [
            "Heading Stability",
            "strong text",
            "quiet emphasis",
            "inline code",
            "a stable link",
            "Secondary Heading",
            "Checked item",
            "linked text",
            "quote keeps",
            "Alpha",
            "positions",
            "doNotMove"
        ];

        return needles
            .Select(needle => (needle, index: markdown.IndexOf(needle, StringComparison.Ordinal)))
            .Where(item => item.index >= 0)
            .Select(item => new Probe(item.needle, new TextRange(item.index, item.needle.Length)))
            .ToArray();
    }

    private static IReadOnlyList<int> MakeCursorLocations(string markdown)
    {
        string[] needles =
        [
            "#",
            "paragraph",
            "**strong",
            "_quiet",
            "`inline",
            "[a stable",
            "##",
            "- [x]",
            "- [ ]",
            "> A quote",
            "| One",
            "```swift",
            "assert"
        ];

        var locations = needles
            .Select(needle => markdown.IndexOf(needle, StringComparison.Ordinal))
            .Where(index => index >= 0)
            .ToList();
        locations.Add(markdown.Length);
        return locations;
    }

    private static IReadOnlyDictionary<string, IReadOnlyList<MarkdownStyleRole>> ContentRolesForProbes(MarkdownStyleSnapshot snapshot, IReadOnlyList<Probe> probes)
    {
        return probes.ToDictionary(
            probe => probe.Name,
            probe => (IReadOnlyList<MarkdownStyleRole>)snapshot.Runs
                .Where(run => run.Role is not MarkdownStyleRole.Base and not MarkdownStyleRole.SyntaxHidden and not MarkdownStyleRole.SyntaxVisible and not MarkdownStyleRole.TableSeparatorHidden)
                .Where(run => run.Range.Intersects(probe.Range))
                .Select(run => run.Role)
                .Distinct()
                .OrderBy(role => role.ToString())
                .ToArray());
    }
}
