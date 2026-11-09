// Copyright © 2026 Dennis Stewart. All rights reserved.

import XCTest
@testable import BrewBarKit

final class ReadmeFormatterTests: XCTestCase {

    func testStripsBadgesImagesAndHTML() {
        let markdown = """
        # My Tool

        <!-- hidden comment -->
        [![Build](https://img.shields.io/badge.svg)](https://ci.example.com)
        <p align="center"><img src="screenshot.png"></p>

        A command-line tool.
        """

        let text = ReadmeFormatter.plainText(from: markdown)

        XCTAssertFalse(text.contains("hidden comment"))
        XCTAssertFalse(text.contains("<p"))
        XCTAssertFalse(text.contains("img.shields.io"))
        XCTAssertFalse(text.contains("screenshot.png"))
        XCTAssertTrue(text.contains("My Tool"))
        XCTAssertTrue(text.contains("A command-line tool."))
    }

    func testConvertsLinksAndHeadingsToPlainText() {
        let markdown = """
        ## Installation

        Run [Homebrew](https://brew.sh) first.
        """

        let text = ReadmeFormatter.plainText(from: markdown)

        XCTAssertEqual(text, "Installation\n\nRun Homebrew first.")
    }

    func testConvertsBulletsAndRemovesRules() {
        let markdown = """
        Features
        - Fast
        * Simple
        + Local

        ---
        """

        let text = ReadmeFormatter.plainText(from: markdown)

        XCTAssertTrue(text.contains("• Fast"))
        XCTAssertTrue(text.contains("• Simple"))
        XCTAssertTrue(text.contains("• Local"))
        XCTAssertFalse(text.contains("---"))
    }

    func testCollapsesBlankLinesAndTrims() {
        let markdown = "\n\n\nFirst\n\n\n\n\nSecond\n\n\n"

        XCTAssertEqual(ReadmeFormatter.plainText(from: markdown), "First\n\nSecond")
    }

    func testTruncatesWithEllipsisAtLimit() {
        let markdown = String(repeating: "abcdefghij", count: 20)

        let text = ReadmeFormatter.plainText(from: markdown, limit: 25)

        XCTAssertEqual(text.count, 26)
        XCTAssertTrue(text.hasSuffix("…"))
        XCTAssertEqual(String(text.dropLast()), String(markdown.prefix(25)))
    }

    func testEmptyInputProducesEmptyString() {
        XCTAssertEqual(ReadmeFormatter.plainText(from: "   \n\n"), "")
    }
}
