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
    private MarkdownMinimapViewportMetrics? metrics;

    public event Action<double>? ScrollRatioRequested;

    public MarkdownMinimapView()
    {
        InitializeComponent();
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
        var y = 6.0;
        var lineHeight = Math.Max(2.0, (height - 12) / Math.Max(1, lines.Count));

        foreach (var line in lines)
        {
            var rect = new Rectangle
            {
                Width = WidthFor(line, width),
                Height = HeightFor(line, lineHeight),
                Fill = BrushFor(line),
                RadiusX = 1,
                RadiusY = 1,
                Opacity = line.Kind.Name == "blank" ? 0.0 : 0.82
            };
            Canvas.SetLeft(rect, XFor(line));
            Canvas.SetTop(rect, y);
            MinimapCanvas.Children.Add(rect);
            y += lineHeight;
        }

        metrics = MarkdownMinimapViewport.Metrics(
            new RectD(0, 0, width, height),
            currentDocumentHeight,
            new RectD(0, currentVisibleMinY, width, currentVisibleHeight),
            horizontalInset: 4,
            minimumThumbHeight: 10);

        var thumb = new Rectangle
        {
            Width = metrics.ThumbRect.Width,
            Height = metrics.ThumbRect.Height,
            Stroke = new SolidColorBrush(ColorFromHex(0x0C, 0x74, 0xB8)),
            StrokeThickness = 1,
            Fill = new SolidColorBrush(global::Windows.UI.Color.FromArgb(34, 12, 116, 184)),
            RadiusX = 3,
            RadiusY = 3
        };
        Canvas.SetLeft(thumb, metrics.ThumbRect.X);
        Canvas.SetTop(thumb, metrics.ThumbRect.Y);
        MinimapCanvas.Children.Add(thumb);
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

    private static double WidthFor(MarkdownMinimapLine line, double width)
    {
        var baseWidth = line.Kind.Name switch
        {
            "heading" => 0.82,
            "tableHeader" or "tableRow" => 0.72,
            "code" or "codeFence" => 0.68,
            "quote" => 0.58,
            "taskList" or "unorderedList" or "orderedList" => 0.62,
            _ => 0.50
        };
        var textFactor = Math.Min(1.0, Math.Max(0.18, line.TextLength / 80.0));
        return Math.Max(8, width * baseWidth * textFactor);
    }

    private static double HeightFor(MarkdownMinimapLine line, double lineHeight)
    {
        return line.Kind.Name == "heading" ? Math.Max(2.5, lineHeight * 0.72) : Math.Max(1.5, lineHeight * 0.48);
    }

    private static double XFor(MarkdownMinimapLine line)
    {
        return 6 + line.QuoteDepth * 5 + line.Kind.Depth * 3;
    }

    private static Brush BrushFor(MarkdownMinimapLine line)
    {
        var color = line.Kind.Name switch
        {
            "heading" => ColorFromHex(0x20, 0x24, 0x2A),
            "code" or "codeFence" => ColorFromHex(0x6A, 0x72, 0x80),
            "quote" => ColorFromHex(0x97, 0xA0, 0xAD),
            "taskList" => line.Kind.Checked ? ColorFromHex(0x0C, 0x74, 0xB8) : ColorFromHex(0x97, 0xA0, 0xAD),
            _ => ColorFromHex(0xB5, 0xBD, 0xC8)
        };
        return new SolidColorBrush(color);
    }

    private static global::Windows.UI.Color ColorFromHex(byte red, byte green, byte blue)
    {
        return global::Windows.UI.Color.FromArgb(255, red, green, blue);
    }
}
