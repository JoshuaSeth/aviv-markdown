namespace Aviv.Windows.Core;

public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
    public double MidY => Y + Height / 2;
}

public sealed record MarkdownMinimapViewportMetrics(
    RectD TrackRect,
    double DocumentHeight,
    double VisibleMinY,
    double VisibleHeight,
    RectD ThumbRect)
{
    public double VisibleMaxY => VisibleMinY + VisibleHeight;
    public double ScrollableDocumentHeight => Math.Max(0, DocumentHeight - VisibleHeight);

    public double ProjectedY(double documentY)
    {
        var clampedY = Math.Min(Math.Max(0, documentY), DocumentHeight);
        return TrackRect.MinY + clampedY / Math.Max(1, DocumentHeight) * TrackRect.Height;
    }

    public double ProjectedHeight(double documentHeight)
    {
        return Math.Max(0, documentHeight / Math.Max(1, DocumentHeight) * TrackRect.Height);
    }

    public double DocumentOffsetForThumbMinY(double thumbMinY)
    {
        if (ScrollableDocumentHeight <= 0)
        {
            return 0;
        }

        var scrollableTrackHeight = Math.Max(1, TrackRect.Height - ThumbRect.Height);
        var clampedY = Math.Min(Math.Max(TrackRect.MinY, thumbMinY), TrackRect.MaxY - ThumbRect.Height);
        var ratio = (clampedY - TrackRect.MinY) / scrollableTrackHeight;
        return ratio * ScrollableDocumentHeight;
    }

    public double DocumentOffsetCenteredAtTrackY(double trackY)
    {
        if (ScrollableDocumentHeight <= 0)
        {
            return 0;
        }

        var clampedTrackY = Math.Min(Math.Max(TrackRect.MinY, trackY), TrackRect.MaxY);
        var documentCenterY = (clampedTrackY - TrackRect.MinY) / Math.Max(1, TrackRect.Height) * DocumentHeight;
        return Math.Min(Math.Max(0, documentCenterY - VisibleHeight / 2), ScrollableDocumentHeight);
    }
}

public static class MarkdownMinimapViewport
{
    public static MarkdownMinimapViewportMetrics Metrics(
        RectD trackBounds,
        double documentHeight,
        RectD visibleRect,
        double horizontalInset = 0,
        double minimumThumbHeight = 1.5)
    {
        var trackRect = new RectD(
            trackBounds.MinX + horizontalInset,
            trackBounds.MinY,
            Math.Max(1, trackBounds.Width - horizontalInset * 2),
            Math.Max(1, trackBounds.Height));
        var resolvedDocumentHeight = Math.Max(1, documentHeight);
        var visibleHeight = Math.Min(resolvedDocumentHeight, Math.Max(0, visibleRect.Height));
        var maxVisibleMinY = Math.Max(0, resolvedDocumentHeight - visibleHeight);
        var visibleMinY = Math.Min(Math.Max(0, visibleRect.MinY), maxVisibleMinY);
        var visibleMaxY = visibleMinY + visibleHeight;

        var projectedMinY = trackRect.MinY + visibleMinY / resolvedDocumentHeight * trackRect.Height;
        var projectedMaxY = trackRect.MinY + visibleMaxY / resolvedDocumentHeight * trackRect.Height;
        var exactHeight = Math.Max(0, projectedMaxY - projectedMinY);
        var resolvedMinimumHeight = Math.Min(trackRect.Height, Math.Max(0, minimumThumbHeight));

        double thumbHeight;
        double thumbY;
        if (exactHeight >= resolvedMinimumHeight)
        {
            thumbHeight = exactHeight;
            thumbY = projectedMinY;
        }
        else
        {
            thumbHeight = resolvedMinimumHeight;
            var projectedCenterY = (projectedMinY + projectedMaxY) / 2;
            thumbY = Math.Min(Math.Max(trackRect.MinY, projectedCenterY - thumbHeight / 2), trackRect.MaxY - thumbHeight);
        }

        return new MarkdownMinimapViewportMetrics(
            trackRect,
            resolvedDocumentHeight,
            visibleMinY,
            visibleHeight,
            new RectD(trackRect.MinX, thumbY, trackRect.Width, thumbHeight));
    }
}
