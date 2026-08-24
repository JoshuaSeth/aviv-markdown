import AppKit

final class RemoteSyncIndicatorView: NSView {
    static let indicatorIdentifiers = [
        "remote-source-badge",
        "remote-source-heartbeat",
        "remote-status-shimmer",
    ]

    private let iconView = NSImageView()
    private let sourceLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let heartbeatView = NSView()
    private let shimmerLayer = CAGradientLayer()
    private var currentPresentation: RemoteSyncPresentation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        shimmerLayer.frame = bounds
        heartbeatView.layer?.cornerRadius = heartbeatView.bounds.height / 2
    }

    func update(_ presentation: RemoteSyncPresentation, theme: MarkdownTheme) {
        currentPresentation = presentation
        isHidden = false
        sourceLabel.stringValue = presentation.sourceHost
        detailLabel.stringValue = presentation.detail
        sourceLabel.font = NSFont.systemFont(
            ofSize: theme.scaledMetric(11.5, minimum: 10),
            weight: .semibold
        )
        detailLabel.font = NSFont.systemFont(
            ofSize: theme.scaledMetric(10.5, minimum: 9),
            weight: .medium
        )
        sourceLabel.textColor = theme.textColor.withAlphaComponent(0.82)
        detailLabel.textColor = phaseColor(presentation.phase, theme: theme)
        iconView.contentTintColor = theme.accentColor.withAlphaComponent(0.82)
        heartbeatView.layer?.backgroundColor =
            phaseColor(
                presentation.phase,
                theme: theme
            ).cgColor
        setAccessibilityLabel(
            "Remote Markdown source \(presentation.sourceHost), \(presentation.detail)"
        )
        animateHeartbeat()
        if [.incomingApplied, .saved, .conflict].contains(presentation.phase) {
            animateShimmer(theme: theme)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 0.14).cgColor
        layer?.borderWidth = 1
        setAccessibilityElement(true)
        setAccessibilityIdentifier("remote-source-badge")

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: "network",
            accessibilityDescription: "Remote source"
        )
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.lineBreakMode = .byTruncatingTail
        heartbeatView.translatesAutoresizingMaskIntoConstraints = false
        heartbeatView.wantsLayer = true
        heartbeatView.setAccessibilityElement(true)
        heartbeatView.setAccessibilityIdentifier("remote-source-heartbeat")
        heartbeatView.setAccessibilityLabel("Remote source heartbeat")

        layer?.addSublayer(shimmerLayer)
        shimmerLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.55).cgColor,
            NSColor.clear.cgColor,
        ]
        shimmerLayer.locations = [-0.35, -0.15, 0.05]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)

        addSubview(iconView)
        addSubview(sourceLabel)
        addSubview(detailLabel)
        addSubview(heartbeatView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),
            sourceLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            sourceLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 118),
            detailLabel.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 7),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heartbeatView.leadingAnchor.constraint(
                equalTo: detailLabel.trailingAnchor,
                constant: 7
            ),
            heartbeatView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            heartbeatView.centerYAnchor.constraint(equalTo: centerYAnchor),
            heartbeatView.widthAnchor.constraint(equalToConstant: 7),
            heartbeatView.heightAnchor.constraint(equalToConstant: 7),
        ])
        isHidden = true
    }

    private func phaseColor(_ phase: RemoteSyncPhase, theme: MarkdownTheme) -> NSColor {
        switch phase {
        case .conflict, .error:
            return NSColor(calibratedRed: 0.78, green: 0.23, blue: 0.18, alpha: 1)
        case .saving, .connecting, .checking:
            return NSColor(calibratedRed: 0.73, green: 0.48, blue: 0.08, alpha: 1)
        case .readOnly:
            return theme.secondaryTextColor
        case .watching, .incomingApplied, .saved:
            return NSColor(calibratedRed: 0.08, green: 0.53, blue: 0.38, alpha: 1)
        }
    }

    private func animateHeartbeat() {
        heartbeatView.layer?.removeAnimation(forKey: "remote-heartbeat")
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.82
        pulse.toValue = 1.22
        pulse.duration = 0.42
        pulse.autoreverses = true
        heartbeatView.layer?.add(pulse, forKey: "remote-heartbeat")
    }

    private func animateShimmer(theme: MarkdownTheme) {
        shimmerLayer.removeAnimation(forKey: "remote-shimmer")
        shimmerLayer.colors = [
            NSColor.clear.cgColor,
            theme.accentColor.withAlphaComponent(0.17).cgColor,
            NSColor.clear.cgColor,
        ]
        let shimmer = CABasicAnimation(keyPath: "locations")
        shimmer.fromValue = [-0.35, -0.15, 0.05]
        shimmer.toValue = [0.95, 1.15, 1.35]
        shimmer.duration = 0.9
        shimmer.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerLayer.add(shimmer, forKey: "remote-shimmer")
    }
}
