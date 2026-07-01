import AppKit
import AvivCore
import Foundation

let arguments = CommandLine.arguments

if arguments.contains("--verify-layout") {
    exit(MarkdownLayoutVerifier.runCLI())
}

if arguments.contains("--verify-minimap") {
    exit(MarkdownMinimapVerifier.runCLI())
}

if arguments.contains("--verify-scroll-jitter") {
    exit(MarkdownScrollJitterVerifier.runCLI())
}

if arguments.contains("--verify-scroll-bounds") {
    exit(MarkdownScrollBoundsVerifier.runCLI())
}

if arguments.contains("--verify-commands") {
    exit(AppCommandVerifier.runCLI())
}

if arguments.contains("--verify-tabs") {
    exit(AppTabVerifier.runCLI())
}

if arguments.contains("--verify-default-app-prompt") {
    exit(MarkdownDefaultAppService.verifyPromptLogicForCLI())
}

if let snapshotIndex = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(snapshotIndex + 1) {
    let path = arguments[snapshotIndex + 1]
    let cursorNeedle: String?
    if let cursorIndex = arguments.firstIndex(of: "--cursor"), arguments.indices.contains(cursorIndex + 1) {
        cursorNeedle = arguments[cursorIndex + 1]
    } else {
        cursorNeedle = nil
    }
    let viewScale: CGFloat?
    if let zoomIndex = arguments.firstIndex(of: "--zoom"), arguments.indices.contains(zoomIndex + 1) {
        viewScale = Double(arguments[zoomIndex + 1]).map { CGFloat($0) }
    } else {
        viewScale = nil
    }
    let scrollRatio: CGFloat?
    if let scrollIndex = arguments.firstIndex(of: "--scroll"), arguments.indices.contains(scrollIndex + 1) {
        scrollRatio = Double(arguments[scrollIndex + 1]).map { CGFloat($0) }
    } else {
        scrollRatio = nil
    }
    let documentFormat = snapshotDocumentFormat(arguments: arguments)
    let markdown: String
    let baseURL: URL?
    if let markdownIndex = arguments.firstIndex(of: "--markdown"), arguments.indices.contains(markdownIndex + 1) {
        let markdownURL = URL(fileURLWithPath: arguments[markdownIndex + 1])
        markdown = (try? String(contentsOf: markdownURL, encoding: .utf8)) ?? MarkdownSamples.starter
        baseURL = markdownURL.deletingLastPathComponent()
    } else {
        markdown = MarkdownSamples.starter
        baseURL = nil
    }

    do {
        try MarkdownSnapshotRenderer.renderSample(to: URL(fileURLWithPath: path), cursorNeedle: cursorNeedle, viewScale: viewScale, markdown: markdown, baseURL: baseURL, scrollRatio: scrollRatio, documentFormat: documentFormat)
        print("snapshot: \(path)")
        exit(0)
    } catch {
        fputs("snapshot failed: \(error)\n", stderr)
        exit(1)
    }
}

if let printSnapshotIndex = arguments.firstIndex(of: "--snapshot-print"), arguments.indices.contains(printSnapshotIndex + 1) {
    let path = arguments[printSnapshotIndex + 1]
    let documentFormat = snapshotDocumentFormat(arguments: arguments)
    let markdown: String
    let baseURL: URL?
    if let markdownIndex = arguments.firstIndex(of: "--markdown"), arguments.indices.contains(markdownIndex + 1) {
        let markdownURL = URL(fileURLWithPath: arguments[markdownIndex + 1])
        markdown = (try? String(contentsOf: markdownURL, encoding: .utf8)) ?? MarkdownSamples.starter
        baseURL = markdownURL.deletingLastPathComponent()
    } else {
        markdown = MarkdownSamples.starter
        baseURL = nil
    }

    do {
        try MarkdownSnapshotRenderer.renderPrintSample(to: URL(fileURLWithPath: path), format: documentFormat, markdown: markdown, baseURL: baseURL)
        print("snapshot: \(path)")
        exit(0)
    } catch {
        fputs("snapshot failed: \(error)\n", stderr)
        exit(1)
    }
}

if let minimapSnapshotIndex = arguments.firstIndex(of: "--snapshot-minimap"), arguments.indices.contains(minimapSnapshotIndex + 1) {
    let path = arguments[minimapSnapshotIndex + 1]
    let scrollRatio: CGFloat
    if let scrollIndex = arguments.firstIndex(of: "--scroll"), arguments.indices.contains(scrollIndex + 1),
       let parsed = Double(arguments[scrollIndex + 1]) {
        scrollRatio = CGFloat(parsed)
    } else {
        scrollRatio = 0
    }
    let viewScale: CGFloat?
    if let zoomIndex = arguments.firstIndex(of: "--zoom"), arguments.indices.contains(zoomIndex + 1) {
        viewScale = Double(arguments[zoomIndex + 1]).map { CGFloat($0) }
    } else {
        viewScale = nil
    }

    do {
        try MarkdownSnapshotRenderer.renderMinimapFixture(to: URL(fileURLWithPath: path), scrollRatio: scrollRatio, viewScale: viewScale)
        print("snapshot: \(path)")
        exit(0)
    } catch {
        fputs("snapshot failed: \(error)\n", stderr)
        exit(1)
    }
}

if let scrollStabilitySnapshotIndex = arguments.firstIndex(of: "--snapshot-scroll-stability"), arguments.indices.contains(scrollStabilitySnapshotIndex + 1) {
    let path = arguments[scrollStabilitySnapshotIndex + 1]
    do {
        try MarkdownScrollJitterVerifier.renderSnapshot(to: URL(fileURLWithPath: path))
        print("snapshot: \(path)")
        exit(0)
    } catch {
        fputs("snapshot failed: \(error)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

private func snapshotDocumentFormat(arguments: [String]) -> MarkdownDocumentFormat {
    guard
        let formatIndex = arguments.firstIndex(of: "--format"),
        arguments.indices.contains(formatIndex + 1),
        let format = MarkdownDocumentFormat(rawValue: arguments[formatIndex + 1].lowercased())
    else {
        return .blog
    }
    return format
}
