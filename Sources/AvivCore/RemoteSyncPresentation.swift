import Foundation

public enum RemoteSyncPhase: String, Equatable, Sendable {
    case connecting
    case watching
    case checking
    case incomingApplied
    case saving
    case saved
    case conflict
    case readOnly
    case error
}

public struct RemoteSyncPresentation: Equatable, Sendable {
    public let phase: RemoteSyncPhase
    public let sourceHost: String
    public let isWritable: Bool
    public let detail: String

    public init(
        phase: RemoteSyncPhase,
        sourceHost: String,
        isWritable: Bool,
        detail: String
    ) {
        self.phase = phase
        self.sourceHost = sourceHost
        self.isWritable = isWritable
        self.detail = detail
    }
}

public struct ExternalMarkdownUpdateResult: Equatable, Sendable {
    public let mappedSelections: [NSRange]
    public let visibleAnchorCharacter: Int?
    public let visibleAnchorDelta: CGFloat
    public let textContainerWidthDelta: CGFloat

    public init(
        mappedSelections: [NSRange],
        visibleAnchorCharacter: Int?,
        visibleAnchorDelta: CGFloat,
        textContainerWidthDelta: CGFloat
    ) {
        self.mappedSelections = mappedSelections
        self.visibleAnchorCharacter = visibleAnchorCharacter
        self.visibleAnchorDelta = visibleAnchorDelta
        self.textContainerWidthDelta = textContainerWidthDelta
    }
}
