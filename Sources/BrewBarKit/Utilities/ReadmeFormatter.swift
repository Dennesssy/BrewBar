// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Turns a GitHub README into readable plain text. The App Store shows a
/// curated description rather than a repository's raw Markdown, so badges,
/// HTML, screenshots, and link syntax are stripped before display.
public enum ReadmeFormatter {
    public static func plainText(from markdown: String, limit: Int = 8_000) -> String {
        var text = markdown

        text = text.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Images and badge shields: ![alt](url)
        text = text.replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^)]*\\)",
            with: "",
            options: .regularExpression
        )
        // Badge links are often [![alt](img)](url); the image pass above
        // leaves an empty []() wrapper behind.
        text = text.replacingOccurrences(
            of: "\\[\\]\\([^)]*\\)",
            with: "",
            options: .regularExpression
        )
        // Links: [label](url) -> label
        text = text.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )

        text = text.replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^>\\s?", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "• ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^\\s*([-*_]\\s*){3,}$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "```[a-zA-Z0-9+_-]*\\n", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
