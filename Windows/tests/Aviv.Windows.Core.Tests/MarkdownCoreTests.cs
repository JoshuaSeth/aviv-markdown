using Aviv.Windows.Core;

namespace Aviv.Windows.Core.Tests;

public sealed class MarkdownCoreTests
{
    [Fact]
    public void CommandCatalogKeepsMacParityIdentifiersAndShortcuts()
    {
        var identifiers = AppCommandCatalog.Commands.Select(command => command.Identifier).ToHashSet();

        string[] required =
        [
            "new",
            "newTab",
            "open",
            "close",
            "save",
            "saveAs",
            "print",
            "undo",
            "redo",
            "pasteAndMatchStyle",
            "find",
            "findAndReplace",
            "actualSize",
            "zoomIn",
            "zoomOut",
            "bold",
            "italic",
            "code",
            "heading1",
            "heading2",
            "showPreviousTab",
            "showNextTab",
            "moveTabToNewWindow",
            "mergeAllWindows"
        ];

        Assert.All(required, identifier => Assert.Contains(identifier, identifiers));
        Assert.Equal("T", AppCommandCatalog.Command("newTab")!.Key);
        Assert.Equal(AvivKeyModifiers.Ctrl, AppCommandCatalog.Command("newTab")!.Modifiers);
        Assert.Equal(AvivKeyModifiers.Ctrl | AvivKeyModifiers.Shift, AppCommandCatalog.Command("saveAs")!.Modifiers);
    }

    [Fact]
    public void TableParserFindsHeaderSeparatorAndRowsOutsideFences()
    {
        const string markdown = """
        | One | Two |
        | --- | --- |
        | Alpha | Beta |

        ```text
        | Not | Table |
        | --- | --- |
        ```
        """;

        var block = Assert.Single(MarkdownTableParser.Blocks(markdown));

        Assert.Equal(3, block.Rows.Count);
        Assert.True(block.Rows[0].IsHeader);
        Assert.True(block.Rows[1].IsSeparator);
        Assert.Equal("Alpha", block.Rows[2].Cells[0].Text);
        Assert.Equal("Beta", block.Rows[2].Cells[1].Text);
    }

    [Fact]
    public void SourceSpanParserFindsEditableLinksAndImages()
    {
        const string markdown = "See [a stable link](https://example.com/stable) and ![diagram](images/a_(b).png).";

        var linkLocation = markdown.IndexOf("stable link", StringComparison.Ordinal);
        var imageLocation = markdown.IndexOf("diagram", StringComparison.Ordinal);

        var link = MarkdownSourceSpanParser.EditableSpanContaining(linkLocation, markdown);
        var image = MarkdownSourceSpanParser.EditableSpanContaining(imageLocation, markdown);

        Assert.NotNull(link);
        Assert.Equal(MarkdownEditableSourceKind.Link, link.Kind);
        Assert.Equal("[a stable link](https://example.com/stable)", link.Source);
        Assert.NotNull(image);
        Assert.Equal(MarkdownEditableSourceKind.Image, image.Kind);
        Assert.Equal("![diagram](images/a_(b).png)", image.Source);
    }

    [Fact]
    public void AnnotationParserRevealsInlineSyntaxOnlyOnFocusedLine()
    {
        const string markdown = "First **bold** line\nSecond _quiet_ line";
        var focus = markdown.IndexOf("bold", StringComparison.Ordinal);

        var tokens = MarkdownAnnotationParser.Tokens(markdown, [new TextRange(focus, 0)]);

        Assert.Contains(tokens, token => token.Label == "**" && token.Role == MarkdownAnnotationRole.InlineDelimiter);
        Assert.DoesNotContain(tokens, token => token.Label == "_" && token.Role == MarkdownAnnotationRole.InlineDelimiter);
    }

    [Fact]
    public void StylerMarksBlocksAndInlineContentLikeTheMacEditor()
    {
        var runs = new MarkdownStyler().RunsFor(MarkdownSamples.LayoutFixture, [new TextRange(0, 0)]);

        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.Heading && run.Detail == "1");
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.Bold);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.Italic);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.InlineCode);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.LinkText);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.TaskMarkerChecked);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.TaskMarkerUnchecked);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.Quote);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.Table);
        Assert.Contains(runs, run => run.Role == MarkdownStyleRole.CodeBlock);
    }

    [Fact]
    public void MinimapStructureRecognizesMarkdownBlocks()
    {
        var lines = MarkdownMinimapStructure.Lines(MarkdownSamples.LayoutFixture);

        Assert.Contains(lines, line => line.Kind.Name == "heading" && line.Kind.Level == 1);
        Assert.Contains(lines, line => line.Kind.Name == "taskList" && line.Kind.Checked);
        Assert.Contains(lines, line => line.Kind.Name == "taskList" && !line.Kind.Checked);
        Assert.Contains(lines, line => line.Kind.Name == "quote" && line.QuoteDepth == 1);
        Assert.Contains(lines, line => line.Kind.Name == "tableHeader" && line.Kind.Columns == 2);
        Assert.Contains(lines, line => line.Kind.Name == "codeFence");
        Assert.Contains(lines, line => line.Kind.Name == "code");
    }

    [Fact]
    public void MinimapViewportProjectsVisibleDocumentRegionAndDragOffsets()
    {
        var metrics = MarkdownMinimapViewport.Metrics(
            new RectD(0, 0, 80, 400),
            documentHeight: 2000,
            visibleRect: new RectD(0, 500, 860, 500),
            horizontalInset: 6,
            minimumThumbHeight: 12);

        Assert.Equal(6, metrics.TrackRect.X);
        Assert.Equal(68, metrics.TrackRect.Width);
        Assert.Equal(500, metrics.VisibleMinY);
        Assert.Equal(500, metrics.VisibleHeight);
        Assert.Equal(100, metrics.ThumbRect.Y, precision: 3);
        Assert.Equal(100, metrics.ThumbRect.Height, precision: 3);
        Assert.Equal(1500, metrics.DocumentOffsetForThumbMinY(metrics.TrackRect.MaxY - metrics.ThumbRect.Height), precision: 3);
        Assert.Equal(750, metrics.DocumentOffsetCenteredAtTrackY(metrics.TrackRect.MidY), precision: 3);
    }

    [Fact]
    public void LayoutVerifierKeepsContentRolesStableAcrossCursorPositions()
    {
        var result = MarkdownLayoutVerifier.Verify(MarkdownSamples.LayoutFixture);

        Assert.True(result.Passed, string.Join(Environment.NewLine, result.Failures));
        Assert.True(result.MeasuredSelections >= 12);
    }
}
