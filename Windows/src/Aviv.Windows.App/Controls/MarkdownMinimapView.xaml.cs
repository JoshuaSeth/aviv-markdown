using Aviv.Windows.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace Aviv.Windows.App.Controls;

public sealed partial class MarkdownMinimapView : UserControl
{
    private readonly Canvas MinimapCanvas;
    private MarkdownMinimapViewportMetrics? metrics;

    public event Action<double>? ScrollRatioRequested;

    public MarkdownMinimapView()
    {
        MinimapCanvas = new Canvas
        {
            Background = new SolidColorBrush(Colors.Transparent)
        };
        MinimapCanvas.PointerPressed += OnPointerPressed;
        Content = MinimapCanvas;
        SizeChanged += (_, _) => Render(currentMarkdown, currentVisibleMinY, currentVisibleHeight, currentDocumentHeight);
    }

    private string currentMarkdown = string.Empty;
    private double currentVisibleMinY;
    private double currentVisibleHeight = 1;
    private double currentDocumentHeight = 1;

    public void Render(string markdown, double visibleMinY, double visibleHeight, double documentHeight)
    {
        currentMarkdown = markdown;
        currentVisibleMinY = visibleMinY;
        currentVisibleHeight = Math.Max(1, visibleHeight);
        currentDocumentHeight = Math.Max(currentVisibleHeight, documentHeight);
        MinimapCanvas.Children.Clear();

        var width = Math.Max(1, ActualWidth);
        var height = Math.Max(1, ActualHeight);
        var lines = MarkdownMinimapStructure.Lines(markdown);

        metrics = MarkdownMinimapViewport.Metrics(
            new RectD(0, 0, width, height),
            currentDocumentHeight,
            new RectD(0, currentVisibleMinY, width, currentVisibleHeight),
            horizontalInset: 4,
            minimumThumbHeight: 10);

        AddRect(
            metrics.ThumbRect.X,
            metrics.ThumbRect.Y,
            metrics.ThumbRect.Width,
            metrics.ThumbRect.Height,
            new SolidColorBrush(global::Windows.UI.Color.FromArgb(18, 12, 116, 184)),
            radius: 3,
            stroke: new SolidColorBrush(global::Windows.UI.Color.FromArgb(46, 12, 116, 184)));

        var insetX = 7.0;
        var markerLaneWidth = 13.0;
        var maxLineWidth = Math.Max(8, width - insetX * 2);
        var lineStep = Math.Max(2.1, Math.Min(6.0, (height - 16) / Math.Max(1, lines.Count)));
        var y = 8.0;

        foreach (var line in lines)
        {
            DrawLine(line, y, lineStep, insetX, markerLaneWidth, maxLineWidth);
            y += lineStep;
            if (y > height + lineStep)
            {
                break;
            }
        }
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        if (metrics is null)
        {
            return;
        }

        var y = args.GetCurrentPoint(MinimapCanvas).Position.Y;
        var targetOffset = metrics.DocumentOffsetCenteredAtTrackY(y);
        ScrollRatioRequested?.Invoke(metrics.ScrollableDocumentHeight <= 0 ? 0 : targetOffset / metrics.ScrollableDocumentHeight);
    }

    private void DrawLine(MarkdownMinimapLine line, double y, double lineStep, double insetX, double markerLaneWidth, double maxLineWidth)
    {
        if (line.Kind.Name == "blank")
        {
            return;
        }

        var quoteOffset = Math.Min(5, line.QuoteDepth) * 2.5;
        var contentX = insetX + markerLaneWidth + quoteOffset;
        var contentWidth = Math.Max(8, maxLineWidth - markerLaneWidth - quoteOffset);
        var density = Math.Min(Math.Max(line.TextLength, 8), 96) / 96.0;
        var baseWidth = Math.Max(8, contentWidth * density);

        for (var quoteIndex = 0; quoteIndex < Math.Min(line.QuoteDepth, 3); quoteIndex++)
        {
            AddRect(insetX + quoteIndex * 3.2, y - 1, 1.4, Math.Min(7, Math.Max(2.6, lineStep * 0.66)), Brush(0x66, 0x20, 0x82, 0x74));
        }

        switch (line.Kind.Name)
        {
            case "heading":
                var headingHeight = Math.Min(3.2, Math.Max(1.6, lineStep * 0.74));
                var level = Math.Max(1, Math.Min(6, line.Kind.Level));
                AddRect(insetX + 1, y, Math.Max(3, 6 - level * 0.55), headingHeight, Brush(0xC4, 0x0C, 0x74, 0xB8));
                AddRect(contentX, y, Math.Min(contentWidth, baseWidth + Math.Max(0, 6 - level) * 3), headingHeight, Brush(0xA8, 0x0C, 0x74, 0xB8));
                break;
            case "unorderedList":
            case "orderedList":
                DrawListGlyph(line, y, lineStep, insetX);
                AddRect(contentX + line.Kind.Depth * 2.5, y, baseWidth, Math.Min(1.8, Math.Max(0.9, lineStep * 0.48)), Brush(0x62, 0x6A, 0x72, 0x80));
                break;
            case "taskList":
                DrawListGlyph(line, y, lineStep, insetX);
                AddRect(contentX + line.Kind.Depth * 2.5, y, baseWidth, Math.Min(1.8, Math.Max(0.9, lineStep * 0.48)), line.Kind.Checked ? Brush(0x76, 0x0C, 0x74, 0xB8) : Brush(0x70, 0x97, 0xA0, 0xAD));
                break;
            case "quote":
                AddRect(contentX, y, baseWidth, Math.Min(1.8, Math.Max(0.9, lineStep * 0.48)), Brush(0x62, 0x20, 0x82, 0x74));
                break;
            case "tableHeader":
            case "tableSeparator":
            case "tableRow":
                DrawTableRow(line.Kind.Columns, contentX - 1, y, Math.Max(baseWidth, contentWidth * 0.70), lineStep, line.Kind.Name == "tableHeader" ? 0x94 : line.Kind.Name == "tableSeparator" ? 0x40 : 0x6C);
                break;
            case "codeFence":
                AddRect(insetX + 2, y, 4.2, 1.1, Brush(0x72, 0x6A, 0x72, 0x80));
                AddRect(insetX + 2, y + Math.Min(4.6, Math.Max(2.4, lineStep * 0.58)) - 1.1, 4.2, 1.1, Brush(0x72, 0x6A, 0x72, 0x80));
                AddRect(contentX, y, Math.Min(contentWidth * 0.56, Math.Max(baseWidth, 18)), Math.Min(2.4, Math.Max(1.1, lineStep * 0.44)), Brush(0x7A, 0x6A, 0x72, 0x80));
                break;
            case "code":
                DrawCodeLine(contentX, y, Math.Min(contentWidth * 0.82, Math.Max(baseWidth, 22)), lineStep);
                break;
            case "thematicBreak":
                AddRect(contentX, y, contentWidth * 0.62, Math.Min(1.8, Math.Max(0.9, lineStep * 0.48)), Brush(0x6B, 0x97, 0xA0, 0xAD));
                break;
            default:
                AddRect(contentX, y, baseWidth, Math.Min(1.8, Math.Max(0.9, lineStep * 0.48)), Brush(0x38, 0x20, 0x24, 0x2A));
                break;
        }
    }

    private void DrawListGlyph(MarkdownMinimapLine line, double y, double lineStep, double insetX)
    {
        var size = Math.Min(5.4, Math.Max(3.0, lineStep * 0.56));
        var x = insetX + 2 + Math.Min(line.Kind.Depth, 5) * 2.8;
        var color = line.Kind.Name == "taskList"
            ? line.Kind.Checked ? Brush(0x8F, 0x0C, 0x74, 0xB8) : Brush(0x7A, 0x97, 0xA0, 0xAD)
            : Brush(0x7A, 0x6A, 0x72, 0x80);
        AddRect(x, y - size * 0.2, size, size, color, radius: line.Kind.Name == "unorderedList" ? size / 2 : 1.4);
    }

    private void DrawTableRow(int columns, double x, double y, double width, double lineStep, byte alpha)
    {
        var height = Math.Min(3.0, Math.Max(1.35, lineStep * 0.52));
        var columnCount = Math.Max(1, Math.Min(columns, 5));
        var gap = columnCount > 1 ? 1.3 : 0;
        var cellWidth = Math.Max(2, (width - gap * (columnCount - 1)) / columnCount);

        for (var index = 0; index < columnCount; index++)
        {
            AddRect(x + index * (cellWidth + gap), y, cellWidth, height, Brush(alpha, 0x5C, 0x75, 0x86));
        }
    }

    private void DrawCodeLine(double x, double y, double width, double lineStep)
    {
        var height = Math.Min(2.4, Math.Max(1.1, lineStep * 0.44));
        var segmentWidth = Math.Max(4, width / 4.8);
        var currentX = x;
        foreach (var multiplier in new[] { 1.0, 0.72, 0.46 })
        {
            AddRect(currentX, y, segmentWidth * multiplier, height, Brush(0x5E, 0x6A, 0x72, 0x80));
            currentX += segmentWidth * multiplier + 2;
        }
    }

    private void AddRect(double x, double y, double width, double height, Brush fill, double radius = 1.0, Brush? stroke = null)
    {
        if (width <= 0 || height <= 0)
        {
            return;
        }

        var rect = new Rectangle
        {
            Width = width,
            Height = height,
            Fill = fill,
            Stroke = stroke,
            StrokeThickness = stroke is null ? 0 : 1,
            RadiusX = radius,
            RadiusY = radius
        };
        Canvas.SetLeft(rect, x);
        Canvas.SetTop(rect, y);
        MinimapCanvas.Children.Add(rect);
    }

    private static Brush Brush(byte alpha, byte red, byte green, byte blue)
    {
        return new SolidColorBrush(global::Windows.UI.Color.FromArgb(alpha, red, green, blue));
    }
}
