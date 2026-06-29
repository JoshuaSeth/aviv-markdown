import Foundation

public enum MarkdownPatterns {
    // Supports normal destinations plus one level of balanced parentheses, e.g. /a_(b).
    public static let link = #"!?\[([^\]\n]+)\]\(((?:[^()\n\\]|\\.|\([^()\n]*\))+)\)"#
}
