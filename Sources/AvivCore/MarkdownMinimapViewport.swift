import AppKit

public struct MarkdownMinimapViewportMetrics: Equatable {
    public let trackRect: NSRect
    public let documentHeight: CGFloat
    public let visibleMinY: CGFloat
    public let visibleHeight: CGFloat
    public let thumbRect: NSRect

    public var visibleMaxY: CGFloat {
        visibleMinY + visibleHeight
    }

    public var scrollableDocumentHeight: CGFloat {
        max(0, documentHeight - visibleHeight)
    }

    public func projectedY(forDocumentY documentY: CGFloat) -> CGFloat {
        let clampedY = min(max(0, documentY), documentHeight)
        return trackRect.minY + (clampedY / max(1, documentHeight)) * trackRect.height
    }

    public func projectedHeight(forDocumentHeight height: CGFloat) -> CGFloat {
        max(0, height / max(1, documentHeight) * trackRect.height)
    }

    public func documentOffset(forThumbMinY thumbMinY: CGFloat) -> CGFloat {
        guard scrollableDocumentHeight > 0 else { return 0 }
        let scrollableTrackHeight = max(1, trackRect.height - thumbRect.height)
        let clampedY = min(max(trackRect.minY, thumbMinY), trackRect.maxY - thumbRect.height)
        let ratio = (clampedY - trackRect.minY) / scrollableTrackHeight
        return ratio * scrollableDocumentHeight
    }

    public func documentOffset(centeredAtTrackY trackY: CGFloat) -> CGFloat {
        guard scrollableDocumentHeight > 0 else { return 0 }
        let clampedTrackY = min(max(trackRect.minY, trackY), trackRect.maxY)
        let documentCenterY = ((clampedTrackY - trackRect.minY) / max(1, trackRect.height)) * documentHeight
        return min(max(0, documentCenterY - visibleHeight / 2), scrollableDocumentHeight)
    }
}

public enum MarkdownMinimapViewport {
    public static func metrics(
        trackBounds: NSRect,
        documentHeight: CGFloat,
        visibleRect: NSRect,
        horizontalInset: CGFloat = 0,
        minimumThumbHeight: CGFloat = 1.5
    ) -> MarkdownMinimapViewportMetrics {
        let trackRect = NSRect(
            x: trackBounds.minX + horizontalInset,
            y: trackBounds.minY,
            width: max(1, trackBounds.width - horizontalInset * 2),
            height: max(1, trackBounds.height)
        )
        let resolvedDocumentHeight = max(1, documentHeight)
        let visibleHeight = min(resolvedDocumentHeight, max(0, visibleRect.height))
        let maxVisibleMinY = max(0, resolvedDocumentHeight - visibleHeight)
        let visibleMinY = min(max(0, visibleRect.minY), maxVisibleMinY)
        let visibleMaxY = visibleMinY + visibleHeight

        let projectedMinY = trackRect.minY + (visibleMinY / resolvedDocumentHeight) * trackRect.height
        let projectedMaxY = trackRect.minY + (visibleMaxY / resolvedDocumentHeight) * trackRect.height
        let exactHeight = max(0, projectedMaxY - projectedMinY)
        let resolvedMinimumHeight = min(trackRect.height, max(0, minimumThumbHeight))

        let thumbHeight: CGFloat
        let thumbY: CGFloat
        if exactHeight >= resolvedMinimumHeight {
            thumbHeight = exactHeight
            thumbY = projectedMinY
        } else {
            thumbHeight = resolvedMinimumHeight
            let projectedCenterY = (projectedMinY + projectedMaxY) / 2
            thumbY = min(
                max(trackRect.minY, projectedCenterY - thumbHeight / 2),
                trackRect.maxY - thumbHeight
            )
        }

        return MarkdownMinimapViewportMetrics(
            trackRect: trackRect,
            documentHeight: resolvedDocumentHeight,
            visibleMinY: visibleMinY,
            visibleHeight: visibleHeight,
            thumbRect: NSRect(
                x: trackRect.minX,
                y: thumbY,
                width: trackRect.width,
                height: thumbHeight
            )
        )
    }
}
