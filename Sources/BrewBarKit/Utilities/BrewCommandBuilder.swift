import Foundation

/// Represents a command to be executed, with separate executable path and arguments.
/// This structure prevents shell injection by avoiding string interpolation.
public struct BrewCommand: Sendable, Equatable {
    /// The path to the executable to run.
    public let executablePath: String
    /// The arguments to pass to the executable.
    public let arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }

    /// A display string representation for error messages and logging.
    /// This is NOT used for execution - only for human-readable output.
    public var displayString: String {
        ([executablePath] + arguments).joined(separator: " ")
    }
}

public struct BrewCommandBuilder: Sendable {
    private var brewPath: String
    private var subcommand: String
    private var arguments: [String]
    private var options: [String: String]
    private var flags: [String]

    public init(brewPath: String = HomebrewPath.defaultBrewExecutable) {
        self.brewPath = brewPath
        self.subcommand = ""
        self.arguments = []
        self.options = [:]
        self.flags = []
    }

    public func install(_ formula: String) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "install"
        copy.arguments = [sanitize(formula)]
        return copy
    }

    public func upgrade(_ formula: String? = nil) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "upgrade"
        if let formula = formula {
            copy.arguments = [sanitize(formula)]
        } else {
            copy.arguments = []
        }
        return copy
    }

    public func uninstall(_ formula: String) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "uninstall"
        copy.arguments = [sanitize(formula)]
        return copy
    }

    public func listInstalledInfo() -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "info"
        copy.options["json"] = "v2"
        copy.flags = ["--installed"]
        return copy
    }

    public func outdated(json: Bool = true) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "outdated"
        if json {
            copy.options["json"] = "v2"
        }
        return copy
    }

    public func info(_ formula: String, json: Bool = true) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "info"
        copy.arguments = [sanitize(formula)]
        if json {
            copy.options["json"] = "v2"
        }
        return copy
    }

    public func search(_ query: String) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "search"
        copy.arguments = [sanitize(query)]
        return copy
    }

    /// Sanitizes input by filtering to allowed characters.
    /// Note: This is a defense-in-depth measure. The primary protection against
    /// shell injection is using direct process execution without a shell.
    private func sanitize(_ str: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./@"))
        let filtered = str.unicodeScalars.filter { allowed.contains($0) }
        return String(filtered)
    }

    /// Builds the command as a `BrewCommand` struct with separate executable path and arguments.
    /// This is the secure method that should be used for execution.
    public func buildCommand() -> BrewCommand {
        var args: [String] = []
        if !subcommand.isEmpty {
            args.append(subcommand)
        }
        for flag in flags {
            args.append(flag)
        }
        for (key, value) in options.sorted(by: { $0.key < $1.key }) {
            if value.isEmpty {
                args.append("--\(key)")
            } else {
                args.append("--\(key)=\(value)")
            }
        }
        args.append(contentsOf: arguments)
        return BrewCommand(executablePath: brewPath, arguments: args)
    }

    /// Builds the command as a single string for display purposes only.
    /// WARNING: This should NOT be used for shell execution - use `buildCommand()` instead.
    public func build() -> String {
        return buildCommand().displayString
    }
}
