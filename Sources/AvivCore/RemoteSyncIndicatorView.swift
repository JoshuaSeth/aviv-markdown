import AppKit

final class RemoteSyncIndicatorView: NSView {
    static let indicatorIdentifiers = [
        "remote-source-badge",
        "remote-source-heartbeat",
        "remote-status-shimmer",
    ]

    private let iconView = NSImageView()
    private let heartbeatView = NSView()
    private let shimmerLayer = CAGradientLayer()
    private var currentPresentation: RemoteSyncPresentation?
    private(set) var accessibilitySummaryForTesting = ""

    var visibleTextForTesting: String {
        ""
    }

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
        let stateColor = phaseColor(presentation.phase, theme: theme)
        iconView.contentTintColor = theme.accentColor.withAlphaComponent(0.72)
        heartbeatView.layer?.backgroundColor =
            stateColor.cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.56).cgColor
        layer?.borderColor = stateColor.withAlphaComponent(0.18).cgColor
        accessibilitySummaryForTesting =
            "Live document from \(presentation.sourceHost), \(presentation.detail)"
        setAccessibilityLabel(accessibilitySummaryForTesting)
        toolTip = accessibilitySummaryForTesting
        animateHeartbeat()
        if [.incomingApplied, .saved, .conflict].contains(presentation.phase) {
            animateShimmer(theme: theme)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.56).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 0.12).cgColor
        layer?.borderWidth = 1
        setAccessibilityElement(true)
        setAccessibilityIdentifier("remote-source-badge")

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: "network",
            accessibilityDescription: nil
        )
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 12.5,
            weight: .medium
        )
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
        addSubview(heartbeatView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -1),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            heartbeatView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            heartbeatView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heartbeatView.widthAnchor.constraint(equalToConstant: 6),
            heartbeatView.heightAnchor.constraint(equalToConstant: 6),
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
