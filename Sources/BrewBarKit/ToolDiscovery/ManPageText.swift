// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

public enum ManPageText {
    /// `man -P cat` still emits nroff overstrikes when piped: bold is
    /// `X\bX`, underline is `_\bX`. Collapse each `c\b` pair so only the
    /// final glyph remains (what `col -b` does).
    public static func stripOverstrike(_ text: String) -> String {
        var result: [Character] = []
        result.reserveCapacity(text.count)
        for ch in text {
            if ch == "\u{8}" {
                if !result.isEmpty { result.removeLast() }
            } else {
                result.append(ch)
            }
        }
        return String(result)
    }
}
