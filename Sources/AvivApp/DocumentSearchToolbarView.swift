import AppKit
import AvivCore

@MainActor
final class DocumentSearchToolbarView: NSView, NSSearchFieldDelegate {
    var onQueryChange: ((String) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?

    private let searchField = NSSearchField(frame: .zero)
    private let previousButton = NSButton(frame: .zero)
    private let nextButton = NSButton(frame: .zero)
    private let resultLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(frame: .zero)

    override var intrinsicContentSize: NSSize {
        NSSize(width: 322, height: 28)
    }

    var query: String {
        searchField.stringValue
    }

    var searchFieldFrameForTesting: NSRect {
        searchField.frame
    }

    var previousButtonFrameForTesting: NSRect {
        previousButton.frame
    }

    var nextButtonFrameForTesting: NSRect {
        nextButton.frame
    }

    var resultLabelFrameForTesting: NSRect {
        resultLabel.frame
    }

    var closeButtonFrameForTesting: NSRect {
        closeButton.frame
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 322, height: 28))
        translatesAutoresizingMaskIntoConstraints = false
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setQuery(_ query: String) {
        searchField.stringValue = query
    }

    func focusAndSelectQuery() {
        guard let window else { return }
        window.makeFirstResponder(searchField)
        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(
                location: 0,
                length: (searchField.stringValue as NSString).length
            )
        }
    }

    func updateResultPosition(currentIndex: Int?, totalCount: Int) {
        let summary: String
        if totalCount == 0 {
            summary = query.isEmpty ? "" : "0 / 0"
        } else {
            summary = "\((currentIndex ?? 0) + 1) / \(totalCount)"
        }
        resultLabel.stringValue = summary
        resultLabel.toolTip =
            totalCount == 1 ? "1 search result" : "\(totalCount) search results"
        resultLabel.setAccessibilityValue(summary.isEmpty ? "No active query" : summary)
        resultLabel.setAccessibilityHelp(
            totalCount == 1
                ? "One search result."
                : "\(totalCount) search results."
        )
        previousButton.isEnabled = totalCount > 0
        nextButton.isEnabled = totalCount > 0
    }

    private func configure() {
        setAccessibilityElement(true)
        setAccessibilityIdentifier("aviv.toolbar.search")
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription("Document search controls")
        setAccessibilityLabel("Document search")
        setAccessibilityHelp(
            "Searches the current Markdown document without covering other toolbar controls."
        )
        setAccessibilityEnabled(true)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.controlSize = .small
        searchField.font = MarkdownTheme.clean.smallFont
        searchField.placeholderString = "Find in document"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldSubmitted)
        searchField.setAccessibilityIdentifier("aviv.toolbar.search-field")
        searchField.setAccessibilityLabel("Find in document")
        searchField.setAccessibilityHelp(
            "Enter search text. Press Return for the next result or Shift-Return for the previous result."
        )

        configureNavigationButton(
            previousButton,
            symbolName: "chevron.up",
            label: "Previous search result",
            identifier: "aviv.toolbar.search-previous",
            help: "Moves to the previous search result. Keyboard shortcut: Command-Shift-G.",
            action: #selector(previousResult)
        )
        configureNavigationButton(
            nextButton,
            symbolName: "chevron.down",
            label: "Next search result",
            identifier: "aviv.toolbar.search-next",
            help: "Moves to the next search result. Keyboard shortcut: Command-G.",
            action: #selector(nextResult)
        )

        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: MarkdownTheme.clean.smallFont.pointSize,
            weight: .regular
        )
        resultLabel.textColor = MarkdownTheme.clean.secondaryTextColor
        resultLabel.alignment = .center
        resultLabel.lineBreakMode = .byTruncatingMiddle
        resultLabel.setAccessibilityElement(true)
        resultLabel.setAccessibilityIdentifier("aviv.toolbar.search-status")
        resultLabel.setAccessibilityRole(.staticText)
        resultLabel.setAccessibilityLabel("Search result position")
        resultLabel.setAccessibilityEnabled(true)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close search"
        )
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.target = self
        closeButton.action = #selector(closeSearch)
        closeButton.toolTip = "Closes document search and returns focus to the editor."
        closeButton.setAccessibilityElement(true)
        closeButton.setAccessibilityIdentifier("aviv.toolbar.search-close")
        closeButton.setAccessibilityRole(.button)
        closeButton.setAccessibilityLabel("Close search")
        closeButton.setAccessibilityHelp(
            "Closes document search and returns focus to the editor."
        )
        closeButton.setAccessibilityEnabled(true)

        addSubview(searchField)
        addSubview(previousButton)
        addSubview(nextButton)
        addSubview(resultLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 322),
            heightAnchor.constraint(equalToConstant: 28),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 190),
            searchField.heightAnchor.constraint(equalToConstant: 24),

            previousButton.leadingAnchor.constraint(
                equalTo: searchField.trailingAnchor,
                constant: 4
            ),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 22),
            previousButton.heightAnchor.constraint(equalToConstant: 22),

            nextButton.leadingAnchor.constraint(
                equalTo: previousButton.trailingAnchor,
                constant: 1
            ),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 22),
            nextButton.heightAnchor.constraint(equalToConstant: 22),

            resultLabel.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 6),
            resultLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            resultLabel.widthAnchor.constraint(equalToConstant: 52),

            closeButton.leadingAnchor.constraint(equalTo: resultLabel.trailingAnchor, constant: 3),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        updateResultPosition(currentIndex: nil, totalCount: 0)
    }

    private func configureNavigationButton(
        _ button: NSButton,
        symbolName: String,
        label: String,
        identifier: String,
        help: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .inline
        button.isBordered = true
        button.target = self
        button.action = action
        button.toolTip = help
        button.setAccessibilityElement(true)
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(help)
        button.setAccessibilityEnabled(true)
    }

    func controlTextDidChange(_ notification: Notification) {
        onQueryChange?(searchField.stringValue)
    }

    @objc private func searchFieldSubmitted(_ sender: NSSearchField) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            onPrevious?()
        } else {
            onNext?()
        }
    }

    @objc private func previousResult() {
        onPrevious?()
    }

    @objc private func nextResult() {
        onNext?()
    }

    @objc private func closeSearch() {
        onClose?()
    }
}
