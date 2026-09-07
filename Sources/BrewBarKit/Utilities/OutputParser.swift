import Foundation

public struct BrewListOutput: Codable, Sendable {
    public let formulae: [BrewFormula]
    public let casks: [BrewCask]
}

public struct BrewOutdatedOutput: Codable, Sendable {
    public let formulae: [BrewFormula]
    public let casks: [BrewCask]
}

public struct BrewFormula: Codable, Sendable {
    public let name: String
    public let full_name: String?
    public let desc: String?
    public let installed_versions: [String]?
    public let current_version: String?
    public let outdated: Bool?
    public let homepage: String?
    public let license: String?
}

public struct BrewCask: Codable, Sendable {
    public let token: String
    public let name: [String]?
    public let desc: String?
    public let installed_versions: [String]?
    public let current_version: String?
    public let outdated: Bool?
    public let homepage: String?
}

public struct OutputParser: Sendable {
    public init() {}

    public func parseInstalledPackages(_ jsonString: String) throws -> [FormulaItem] {
        guard let data = jsonString.data(using: .utf8) else {
            throw BrewBarError.parseError("Invalid UTF-8 string")
        }
        let decoder = JSONDecoder()
        let output = try decoder.decode(BrewListOutput.self, from: data)

        var items: [FormulaItem] = []

        for formula in output.formulae {
            let version = formula.installed_versions?.first ?? "unknown"
            items.append(FormulaItem(
                id: formula.name,
                name: formula.name,
                fullTitle: formula.full_name ?? formula.name,
                description: formula.desc ?? "",
                currentVersion: version,
                type: .formula,
                homepage: formula.homepage,
                license: formula.license,
                installedDate: Date(),
                lastChecked: Date()
            ))
        }

        for cask in output.casks {
            let version = cask.installed_versions?.first ?? "unknown"
            let name = cask.name?.first ?? cask.token
            items.append(FormulaItem(
                id: cask.token,
                name: name,
                fullTitle: cask.token,
                description: cask.desc ?? "",
                currentVersion: version,
                type: .cask,
                homepage: cask.homepage,
                installedDate: Date(),
                lastChecked: Date()
            ))
        }

        return items
    }

    public func parseOutdatedPackages(_ jsonString: String) throws -> (formulas: [BrewFormula], casks: [BrewCask]) {
        guard let data = jsonString.data(using: .utf8) else {
            throw BrewBarError.parseError("Invalid UTF-8 string")
        }
        let decoder = JSONDecoder()
        let output = try decoder.decode(BrewOutdatedOutput.self, from: data)
        return (output.formulae, output.casks)
    }
}
