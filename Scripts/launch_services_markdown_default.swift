#!/usr/bin/env swift

import CoreServices
import Foundation
import UniformTypeIdentifiers

private let bundleIDOption = "--bundle-id"
private let expectedBundleID = argument(after: bundleIDOption) ?? "local.aviv.markdown"
private let mode = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "status"
private let roles: [(name: String, mask: LSRolesMask)] = [
    ("all", .all),
    ("editor", .editor),
    ("viewer", .viewer)
]
private let markdownContentTypes = [
    "net.daringfireball.markdown",
    "io.typora.markdown"
]
private let genericTextContentTypes = Set([
    "public.plain-text",
    "public.text",
    "public.data",
    "public.item",
    "public.content"
])
private let markdownExtensions = [
    "md",
    "markdown",
    "mdown",
    "mdwn",
    "mkd",
    "mkdn",
    "mdtxt",
    "mdtext",
    "mmd",
    "rmd",
    "rmarkdown",
    "qmd"
]

switch mode {
case "set":
    exit(setDefaults())
case "force-preferences":
    exit(forcePreferenceDefaults())
case "verify":
    exit(verifyDefaults())
case "status":
    printStatus()
    exit(0)
default:
    fputs("usage: launch_services_markdown_default.swift [set|force-preferences|verify|status] [--bundle-id local.aviv.markdown]\n", stderr)
    exit(64)
}

private func setDefaults() -> Int32 {
    var failed = false

    for contentType in defaultableContentTypes() {
        for role in roles {
            let status = LSSetDefaultRoleHandlerForContentType(contentType as CFString, role.mask, expectedBundleID as CFString)
            if status != noErr {
                failed = true
                fputs("failed to set \(contentType) role \(role.name): OSStatus \(status)\n", stderr)
            }
        }
    }

    if failed {
        return 1
    }

    print("launch-services: set Markdown defaults to \(expectedBundleID)")
    return verifyDefaults()
}

private func forcePreferenceDefaults() -> Int32 {
    let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")

    do {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var root = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: &format
        ) as? [String: Any] else {
            fputs("Launch Services preferences root is not a dictionary\n", stderr)
            return 1
        }

        var handlers = root["LSHandlers"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        let now = Int(Date().timeIntervalSinceReferenceDate)

        let contentTypesToSet = defaultableContentTypes()
        for index in handlers.indices {
            guard let contentType = handlers[index]["LSHandlerContentType"] as? String,
                  contentTypesToSet.contains(contentType) else {
                continue
            }

            handlers[index] = handler(contentType: contentType, modifiedAt: now, preserving: handlers[index])
            seen.insert(contentType)
        }

        for contentType in contentTypesToSet where !seen.contains(contentType) {
            handlers.append(handler(contentType: contentType, modifiedAt: now, preserving: [:]))
        }

        root["LSHandlers"] = handlers
        let output = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try output.write(to: url, options: [.atomic])
        print("launch-services: forced Markdown defaults in \(url.path)")
        return 0
    } catch {
        fputs("failed to update Launch Services preferences: \(error)\n", stderr)
        return 1
    }
}

private func verifyDefaults() -> Int32 {
    var failures: [String] = []

    for contentType in defaultableContentTypes() {
        for role in roles {
            let handler = defaultHandler(for: contentType, role: role.mask)
            if handler != expectedBundleID {
                failures.append("\(contentType) role \(role.name) is \(handler ?? "nil"), expected \(expectedBundleID)")
            }
        }
    }

    for ext in markdownExtensions {
        guard let type = UTType(filenameExtension: ext) else {
            failures.append(".\(ext) does not resolve to a UTType")
            continue
        }

        let handler = defaultHandler(for: type.identifier, role: .all)
        if !genericTextContentTypes.contains(type.identifier), handler != expectedBundleID {
            failures.append(".\(ext) resolves to \(type.identifier), whose default handler is \(handler ?? "nil")")
        }
    }

    if failures.isEmpty {
        print("launch-services: verified Markdown defaults for \(expectedBundleID)")
        return 0
    }

    print("launch-services: verification failed")
    for failure in failures {
        print("- \(failure)")
    }
    return 1
}

private func printStatus() {
    print("bundle: \(expectedBundleID)")
    for contentType in defaultableContentTypes() {
        for role in roles {
            print("\(contentType) [\(role.name)]: \(defaultHandler(for: contentType, role: role.mask) ?? "nil")")
        }
    }
    for ext in markdownExtensions {
        let type = UTType(filenameExtension: ext)?.identifier ?? "nil"
        print(".\(ext): \(type)")
    }
}

private func defaultHandler(for contentType: String, role: LSRolesMask) -> String? {
    guard let unmanaged = LSCopyDefaultRoleHandlerForContentType(contentType as CFString, role) else {
        return nil
    }
    let value = unmanaged.takeRetainedValue()
    return value as String
}

private func defaultableContentTypes() -> [String] {
    var result: [String] = []
    for contentType in markdownContentTypes + markdownExtensions.compactMap({ UTType(filenameExtension: $0)?.identifier }) {
        guard !genericTextContentTypes.contains(contentType), !result.contains(contentType) else {
            continue
        }
        result.append(contentType)
    }
    return result
}

private func handler(contentType: String, modifiedAt: Int, preserving existing: [String: Any]) -> [String: Any] {
    var handler = existing
    handler["LSHandlerContentType"] = contentType
    handler["LSHandlerRoleAll"] = expectedBundleID
    handler["LSHandlerRoleEditor"] = expectedBundleID
    handler["LSHandlerRoleViewer"] = expectedBundleID
    handler["LSHandlerModificationDate"] = modifiedAt
    handler["LSHandlerPreferredVersions"] = [
        "LSHandlerRoleAll": "-",
        "LSHandlerRoleEditor": "-",
        "LSHandlerRoleViewer": "-"
    ]
    return handler
}

private func argument(after option: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: option) else { return nil }
    let valueIndex = CommandLine.arguments.index(after: index)
    guard CommandLine.arguments.indices.contains(valueIndex) else { return nil }
    return CommandLine.arguments[valueIndex]
}
