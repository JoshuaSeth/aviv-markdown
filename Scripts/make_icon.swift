import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: make_icon.swift <output-iconset>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let fileManager = FileManager.default
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

struct IconVariant {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    }
}

let variants = [
    IconVariant(points: 16, scale: 1),
    IconVariant(points: 16, scale: 2),
    IconVariant(points: 32, scale: 1),
    IconVariant(points: 32, scale: 2),
    IconVariant(points: 128, scale: 1),
    IconVariant(points: 128, scale: 2),
    IconVariant(points: 256, scale: 1),
    IconVariant(points: 256, scale: 2),
    IconVariant(points: 512, scale: 1),
    IconVariant(points: 512, scale: 2)
]

for variant in variants {
    let image = NSImage(size: NSSize(width: variant.pixels, height: variant.pixels))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels)
    let radius = CGFloat(variant.pixels) * 0.205
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: CGFloat(variant.pixels) * 0.055, dy: CGFloat(variant.pixels) * 0.055), xRadius: radius, yRadius: radius)

    NSColor(calibratedRed: 0.985, green: 0.986, blue: 0.982, alpha: 1).setFill()
    bounds.fill()
    NSColor.white.setFill()
    background.fill()
    NSColor(calibratedRed: 0.840, green: 0.858, blue: 0.878, alpha: 1).setStroke()
    background.lineWidth = max(1, CGFloat(variant.pixels) * 0.012)
    background.stroke()

    let accent = NSBezierPath()
    accent.move(to: NSPoint(x: CGFloat(variant.pixels) * 0.23, y: CGFloat(variant.pixels) * 0.22))
    accent.line(to: NSPoint(x: CGFloat(variant.pixels) * 0.77, y: CGFloat(variant.pixels) * 0.22))
    accent.lineWidth = max(2, CGFloat(variant.pixels) * 0.036)
    NSColor(calibratedRed: 0.055, green: 0.390, blue: 0.680, alpha: 1).setStroke()
    accent.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = NSFont.systemFont(ofSize: CGFloat(variant.pixels) * 0.50, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.105, green: 0.111, blue: 0.125, alpha: 1),
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    let string = NSString(string: "A")
    let textRect = NSRect(
        x: 0,
        y: CGFloat(variant.pixels) * 0.31,
        width: CGFloat(variant.pixels),
        height: CGFloat(variant.pixels) * 0.54
    )
    string.draw(in: textRect, withAttributes: attributes)

    let markAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: CGFloat(variant.pixels) * 0.16, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.540, green: 0.565, blue: 0.615, alpha: 1),
        .kern: 0
    ]
    NSString(string: "#").draw(
        at: NSPoint(x: CGFloat(variant.pixels) * 0.245, y: CGFloat(variant.pixels) * 0.62),
        withAttributes: markAttributes
    )

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("failed to render icon \(variant.filename)\n", stderr)
        exit(1)
    }

    try png.write(to: outputURL.appendingPathComponent(variant.filename))
}
