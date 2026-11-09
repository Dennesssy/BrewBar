// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Turns man-page or `--help` text into a `CommandNode` tree. Pure, no I/O.
/// Conservative by design: lines that do not clearly match a pattern are skipped.
public enum CommandTreeExtractor {
    private enum Section {
        case none, name, synopsis, options, commands, other
    }

    private static let maxUsageLines = 10
    private static let maxContinuationLines = 3

    public static func parse(toolName: String, text: String) -> CommandNode {
        var section = Section.none
        var nameSummary: String?
        var helpSummary: String?
        var usage: [String] = []
        var options: [CommandOption] = []
        var seenFlags: Set<String> = []
        var subcommands: [CommandNode] = []
        var seenCommands: Set<String> = []

        let lines = text.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let header = headerSection(line: line, trimmed: trimmed) {
                section = header
                continue
            }
            let indent = leadingWidth(line)
            // Any unindented, non-header line closes the section we were in.
            if indent == 0 { section = .other }

            let lower = trimmed.lowercased()
            if lower.hasPrefix("usage:") {
                addUsage(String(trimmed.dropFirst("usage:".count)), to: &usage)
                continue
            }

            if trimmed.hasPrefix("-") {
                let (head, tail) = splitColumns(trimmed)
                let parsed = parseFlags(head)
                if !parsed.flags.isEmpty {
                    let continuation = continuationLines(lines, from: index, indentAbove: indent)
                    index = continuation.next
                    // Dedupe: first occurrence of any flag wins.
                    if parsed.flags.contains(where: { seenFlags.contains($0) }) { continue }
                    seenFlags.formUnion(parsed.flags)
                    let summary = [tail ?? "", continuation.text]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    options.append(CommandOption(flags: parsed.flags, argument: parsed.argument, summary: summary))
                    continue
                }
            }

            switch section {
            case .commands:
                let (name, tail) = splitColumns(trimmed)
                guard isCommandName(name), !seenCommands.contains(name) else { break }
                let continuation = continuationLines(lines, from: index, indentAbove: indent)
                index = continuation.next
                let summary = [tail ?? "", continuation.text]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                seenCommands.insert(name)
                subcommands.append(CommandNode(
                    name: name,
                    summary: summary.isEmpty ? nil : summary,
                    usage: [],
                    options: [],
                    subcommands: []
                ))
            case .name:
                if nameSummary == nil, let range = trimmed.range(of: " - ") {
                    let rest = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { nameSummary = rest }
                }
            case .synopsis:
                addUsage(trimmed, to: &usage)
            case .none, .options, .other:
                break
            }

            // First plain prose line outside a structured section is the fallback summary.
            if helpSummary == nil, section == .none || section == .other,
               !trimmed.hasPrefix("-"), !lower.hasPrefix("usage:"),
               !looksLikeManReference(trimmed) {
                helpSummary = trimmed
            }
        }

        return CommandNode(
            name: toolName,
            summary: nameSummary ?? helpSummary,
            usage: usage,
            options: options,
            subcommands: subcommands
        )
    }

    // MARK: - Sections

    /// `NAME`, `OPTIONS` (man style, column 0) or `Options:` / `Available commands:` (help style).
    private static func headerSection(line: String, trimmed: String) -> Section? {
        guard trimmed.count <= 40 else { return nil }
        let atColumnZero = leadingWidth(line) == 0

        if atColumnZero, isManHeader(trimmed) {
            switch trimmed {
            case "NAME": return .name
            case "SYNOPSIS": return .synopsis
            default: return sectionForLabel(trimmed.lowercased()) ?? .other
            }
        }

        guard trimmed.hasSuffix(":") else { return nil }
        let label = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !label.contains(":"), label.split(separator: " ").count <= 4 else { return nil }
        if let section = sectionForLabel(label.lowercased()) { return section }
        return atColumnZero ? .other : nil
    }

    private static func sectionForLabel(_ label: String) -> Section? {
        if label == "usage" || label == "synopsis" { return .synopsis }
        if label.contains("option") || label.contains("flag") { return .options }
        if label.contains("command") { return .commands }
        return nil
    }

    private static func isManHeader(_ text: String) -> Bool {
        text.contains(where: \.isLetter)
            && text.allSatisfy { $0.isUppercase || $0 == " " || $0 == "-" || $0 == "&" }
    }

    /// `RG(1)`-style page references (man headers and footers), never a summary.
    private static func looksLikeManReference(_ text: String) -> Bool {
        text.range(of: #"\(\d\)"#, options: .regularExpression) != nil
    }

    // MARK: - Usage

    private static func addUsage(_ text: String, to usage: inout [String]) {
        let line = text.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, usage.count < maxUsageLines, !usage.contains(line) else { return }
        usage.append(line)
    }

    // MARK: - Options

    /// `-i, --ignore-case`, `--max-count=NUM`, `--max-count <NUM>`, `-e PATTERN`.
    private static func parseFlags(_ head: String) -> (flags: [String], argument: String?) {
        var flags: [String] = []
        var argument: String?
        let placeholderTrim = CharacterSet(charactersIn: "<>[]=")

        for part in head.split(separator: ",") {
            let spec = part.trimmingCharacters(in: .whitespaces)
            guard spec.hasPrefix("-") else { continue }
            let cut = spec.firstIndex { $0 == "=" || $0 == " " || $0 == "[" || $0 == "<" } ?? spec.endIndex
            let flag = String(spec[..<cut])
            guard isFlag(flag) else { continue }
            flags.append(flag)

            if argument == nil {
                let rest = spec[cut...].trimmingCharacters(in: .whitespaces)
                if let word = rest.split(separator: " ").first {
                    let value = String(word).trimmingCharacters(in: placeholderTrim)
                    if !value.isEmpty { argument = value }
                }
            }
        }
        return (flags, argument)
    }

    /// One or two leading dashes, then a letter or digit, then letters, digits, `-` or `_`.
    private static func isFlag(_ text: String) -> Bool {
        let dashes = text.prefix { $0 == "-" }.count
        let body = text.dropFirst(dashes)
        guard (1...2).contains(dashes), let first = body.first, first.isLetter || first.isNumber else {
            return false
        }
        return body.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    // MARK: - Commands

    /// Lowercase identifiers only, matching `^[a-z][a-z0-9_-]*$`.
    private static func isCommandName(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isLowercase else { return false }
        return text.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }

    // MARK: - Shared helpers

    /// Splits `head   tail` at the first run of two or more spaces or tabs.
    private static func splitColumns(_ text: String) -> (head: String, tail: String?) {
        let chars = Array(text)
        guard chars.count > 1 else { return (text, nil) }
        for index in 0..<(chars.count - 1) where isBlank(chars[index]) && isBlank(chars[index + 1]) {
            let head = String(chars[..<index]).trimmingCharacters(in: .whitespaces)
            let tail = String(chars[index...]).trimmingCharacters(in: .whitespaces)
            return (head, tail.isEmpty ? nil : tail)
        }
        return (text, nil)
    }

    private static func isBlank(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    /// Indented lines after a flag or command, up to `maxContinuationLines`, stopping at blank or less-indented lines.
    private static func continuationLines(
        _ lines: [String],
        from start: Int,
        indentAbove: Int
    ) -> (text: String, next: Int) {
        var parts: [String] = []
        var index = start
        while index < lines.count && parts.count < maxContinuationLines {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, leadingWidth(line) > indentAbove, !trimmed.hasPrefix("-") else { break }
            parts.append(trimmed)
            index += 1
        }
        return (parts.joined(separator: " "), index)
    }

    private static func leadingWidth(_ line: String) -> Int {
        line.prefix { isBlank($0) }.count
    }
}
