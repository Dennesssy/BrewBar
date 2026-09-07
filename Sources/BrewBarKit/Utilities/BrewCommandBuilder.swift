import Foundation

public struct BrewCommandBuilder: Sendable {
    private var brewPath: String
    private var subcommand: String
    private var arguments: [String]
    private var options: [String: String]
    private var flags: [String]

    public init(brewPath: String = "/opt/homebrew/bin/brew") {
        self.brewPath = brewPath
        self.subcommand = ""
        self.arguments = []
        self.options = [:]
        self.flags = []
    }

    public func install(_ formula: String) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "install"
        copy.arguments = [escape(formula)]
        return copy
    }

    public func upgrade(_ formula: String? = nil) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "upgrade"
        if let formula = formula {
            copy.arguments = [escape(formula)]
        } else {
            copy.arguments = []
        }
        return copy
    }

    public func uninstall(_ formula: String) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "uninstall"
        copy.arguments = [escape(formula)]
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
        copy.arguments = [escape(formula)]
        if json {
            copy.options["json"] = "v2"
        }
        return copy
    }

    public func search(_ query: String) -> BrewCommandBuilder {
        var copy = self
        copy.subcommand = "search"
        copy.arguments = [escape(query)]
        return copy
    }

    private func escape(_ str: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./@"))
        let filtered = str.unicodeScalars.filter { allowed.contains($0) }
        return String(filtered)
    }

    public func build() -> String {
        var components = [brewPath]
        if !subcommand.isEmpty {
            components.append(subcommand)
        }
        for flag in flags {
            components.append(flag)
        }
        for (key, value) in options {
            if value.isEmpty {
                components.append("--\(key)")
            } else {
                components.append("--\(key)=\(value)")
            }
        }
        components.append(contentsOf: arguments)
        return components.joined(separator: " ")
    }
}
