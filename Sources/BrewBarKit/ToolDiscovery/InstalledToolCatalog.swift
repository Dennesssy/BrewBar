// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Lists the executables that installed Homebrew formulae place in their kegs.
public struct InstalledToolCatalog: Sendable {
    private let brewPath: String

    public init(brewPath: String = HomebrewPath.defaultBrewExecutable) {
        self.brewPath = brewPath
    }

    /// One installed formula, reduced to the fields discovery needs.
    struct InstalledFormula: Sendable, Equatable {
        let name: String
        let version: String
        let desc: String?
        let isLinked: Bool
    }

    /// Every executable in `<Cellar>/<formula>/<version>/bin`, one entry per binary name.
    public func loadTools() async throws -> [InstalledTool] {
        let builder = BrewCommandBuilder(brewPath: brewPath)
        let brew = builder.executablePath
        let process = ProcessManager()

        let infoJSON = try await process.execute(
            executablePath: brew,
            arguments: builder.listInstalledInfo().buildArguments(),
            timeout: 60,
            extraEnvironment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
        )
        let cellarOutput = try await process.execute(
            executablePath: brew,
            arguments: ["--cellar"],
            timeout: 10
        )
        let cellar = cellarOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cellar.isEmpty else {
            throw BrewBarError.parseError("brew --cellar returned no path")
        }

        let formulae = try Self.parseInstalledFormulae(infoJSON)
            .filter { BrewBarPaths.isSafeComponent($0.name) && BrewBarPaths.isSafeComponent($0.version) }
            .sorted { $0.name < $1.name }

        let fileManager = FileManager.default
        // Binary name -> chosen tool, plus whether its formula is linked.
        var chosen: [String: (tool: InstalledTool, linked: Bool)] = [:]

        for formula in formulae {
            let binDirectory = "\(cellar)/\(formula.name)/\(formula.version)/bin"
            guard let entries = try? fileManager.contentsOfDirectory(atPath: binDirectory) else { continue }

            for entry in entries.sorted() where BrewBarPaths.isSafeComponent(entry) {
                let path = "\(binDirectory)/\(entry)"
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                      !isDirectory.boolValue,
                      fileManager.isExecutableFile(atPath: path)
                else { continue }

                // A linked formula wins a name clash; otherwise the first (alphabetical) one stays.
                if let existing = chosen[entry], existing.linked || !formula.isLinked { continue }

                let tool = InstalledTool(
                    name: entry,
                    formula: formula.name,
                    version: formula.version,
                    path: path,
                    summary: formula.desc
                )
                chosen[entry] = (tool, formula.isLinked)
            }
        }

        return chosen.values.map(\.tool).sorted { $0.name < $1.name }
    }

    /// Pure parse of `brew info --installed --json=v2`. Formulae with no installed version are dropped.
    static func parseInstalledFormulae(_ json: String) throws -> [InstalledFormula] {
        let response = try JSONDecoder().decode(InfoResponse.self, from: Data(json.utf8))
        return response.formulae.compactMap { entry in
            guard let version = entry.installed?.last?.version, !version.isEmpty else { return nil }
            let desc = entry.desc.flatMap { $0.isEmpty ? nil : $0 }
            return InstalledFormula(
                name: entry.name,
                version: version,
                desc: desc,
                isLinked: entry.linkedKeg != nil
            )
        }
    }

    private struct InfoResponse: Decodable {
        let formulae: [FormulaEntry]
    }

    private struct FormulaEntry: Decodable {
        let name: String
        let desc: String?
        let installed: [InstalledEntry]?
        let linkedKeg: String?

        enum CodingKeys: String, CodingKey {
            case name, desc, installed
            case linkedKeg = "linked_keg"
        }
    }

    private struct InstalledEntry: Decodable {
        let version: String
    }
}
