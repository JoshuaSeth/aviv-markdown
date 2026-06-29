import AppKit
import Foundation

public struct MarkdownLayoutVerificationResult {
    public let passed: Bool
    public let failures: [String]
    public let measuredSelections: Int
}

public enum MarkdownLayoutVerifier {
    public static func verify() -> MarkdownLayoutVerificationResult {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 920, height: 1500))
        textView.textContainerInset = NSSize(width: 42, height: 42)
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.loadMarkdown(MarkdownSamples.layoutFixture)

        let probes = makeProbes(in: textView.string)
        var failures: [String] = []
        let cursorLocations = makeCursorLocations(in: textView.string)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let baselineFrames = measure(probes: probes, in: textView)
        let baselineContentAttributes = attributesForContent(probes: probes, in: textView)

        for location in cursorLocations {
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let frames = measure(probes: probes, in: textView)
            let contentAttributes = attributesForContent(probes: probes, in: textView)

            for probe in probes {
                guard let baseline = baselineFrames[probe.name], let current = frames[probe.name] else {
                    failures.append("Missing frame for \(probe.name) at cursor \(location)")
                    continue
                }
                if !rectsMatch(baseline, current) {
                    failures.append("Frame moved for \(probe.name) at cursor \(location): \(baseline.debugDescription) -> \(current.debugDescription)")
                }
                if baselineContentAttributes[probe.name] != contentAttributes[probe.name] {
                    failures.append("Content style shifted for \(probe.name) at cursor \(location)")
                }
            }
        }

        return MarkdownLayoutVerificationResult(
            passed: failures.isEmpty,
            failures: failures,
            measuredSelections: cursorLocations.count
        )
    }

    public static func runCLI() -> Int32 {
        let result = verify()
        if result.passed {
            print("layout-verifier: PASS (\(result.measuredSelections) cursor positions)")
            return 0
        }

        print("layout-verifier: FAIL")
        for failure in result.failures {
            print("- \(failure)")
        }
        return 1
    }

    private struct Probe {
        let name: String
        let range: NSRange
    }

    private static func makeProbes(in string: String) -> [Probe] {
        let ns = string as NSString
        let needles = [
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
        ]

        return needles.compactMap { needle in
            let range = ns.range(of: needle)
            guard range.location != NSNotFound else { return nil }
            return Probe(name: needle, range: range)
        }
    }

    private static func makeCursorLocations(in string: String) -> [Int] {
        let ns = string as NSString
        let needles = [
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
        ]
        var locations = needles.compactMap { needle -> Int? in
            let range = ns.range(of: needle)
            return range.location == NSNotFound ? nil : range.location
        }
        locations.append(ns.length)
        return locations
    }

    private static func measure(probes: [Probe], in textView: NSTextView) -> [String: CGRect] {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return [:] }
        layoutManager.ensureLayout(for: textContainer)
        var frames: [String: CGRect] = [:]
        for probe in probes {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: probe.range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            frames[probe.name] = rounded(rect)
        }
        return frames
    }

    private static func attributesForContent(probes: [Probe], in textView: NSTextView) -> [String: String] {
        guard let storage = textView.textStorage else { return [:] }
        var output: [String: String] = [:]
        for probe in probes {
            let index = min(probe.range.location, max(0, storage.length - 1))
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            let underline = storage.attribute(.underlineStyle, at: index, effectiveRange: nil) as? Int ?? 0
            let strike = storage.attribute(.strikethroughStyle, at: index, effectiveRange: nil) as? Int ?? 0
            output[probe.name] = [
                font?.fontName ?? "nil",
                String(format: "%.2f", font?.pointSize ?? 0),
                colorKey(color),
                "\(underline)",
                "\(strike)"
            ].joined(separator: "|")
        }
        return output
    }

    private static func colorKey(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.deviceRGB) else { return "nil" }
        return String(format: "%.3f,%.3f,%.3f,%.3f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
    }

    private static func rectsMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= 0.5 &&
        abs(lhs.origin.y - rhs.origin.y) <= 0.5 &&
        abs(lhs.size.width - rhs.size.width) <= 0.5 &&
        abs(lhs.size.height - rhs.size.height) <= 0.5
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.origin.x * 100).rounded() / 100,
            y: (rect.origin.y * 100).rounded() / 100,
            width: (rect.size.width * 100).rounded() / 100,
            height: (rect.size.height * 100).rounded() / 100
        )
    }
}
