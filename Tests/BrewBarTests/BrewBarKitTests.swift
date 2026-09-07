import XCTest
@testable import BrewBarKit

final class BrewBarKitTests: XCTestCase {

    func testBrewCommandBuilder() {
        let builder = BrewCommandBuilder(brewPath: "/usr/local/bin/brew")

        // Test install command
        let installCmd = builder.install("python").buildCommand()
        XCTAssertEqual(installCmd.executablePath, "/usr/local/bin/brew")
        XCTAssertEqual(installCmd.arguments, ["install", "python"])
        XCTAssertEqual(installCmd.displayString, "/usr/local/bin/brew install python")

        // Test list installed info command
        let listCmd = builder.listInstalledInfo().buildCommand()
        XCTAssertEqual(listCmd.executablePath, "/usr/local/bin/brew")
        XCTAssertEqual(listCmd.arguments, ["info", "--installed", "--json=v2"])

        // Test outdated command
        let outdatedCmd = builder.outdated(json: true).buildCommand()
        XCTAssertEqual(outdatedCmd.executablePath, "/usr/local/bin/brew")
        XCTAssertEqual(outdatedCmd.arguments, ["outdated", "--json=v2"])

        // Test legacy build() method still works for display
        let legacyString = builder.install("python").build()
        XCTAssertEqual(legacyString, "/usr/local/bin/brew install python")
    }

    func testOutputParser() throws {
        let json = """
        {
            "formulae": [
                {
                    "name": "git",
                    "full_name": "git",
                    "desc": "Distributed revision control system",
                    "installed_versions": ["2.42.0"],
                    "homepage": "https://git-scm.com"
                }
            ],
            "casks": [
                {
                    "token": "visual-studio-code",
                    "name": ["Visual Studio Code"],
                    "desc": "Open-source code editor",
                    "installed_versions": ["1.85.0"],
                    "homepage": "https://code.visualstudio.com"
                }
            ]
        }
        """

        let parser = OutputParser()
        let items = try parser.parseInstalledPackages(json)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "git")
        XCTAssertEqual(items[0].type, .formula)
        XCTAssertEqual(items[1].name, "Visual Studio Code")
        XCTAssertEqual(items[1].type, .cask)
    }

    func testVersionComparator() {
        XCTAssertTrue(VersionComparator.isOutdated(current: "1.0.0", latest: "1.0.1"))
        XCTAssertFalse(VersionComparator.isOutdated(current: "2.0.0", latest: "1.9.9"))
        XCTAssertEqual(VersionComparator.compare("3.11.0", "3.11.0"), .orderedSame)
    }

    func testFormulaItemInitialization() {
        let item = FormulaItem(
            id: "rust",
            name: "rust",
            description: "Empowering everyone to build reliable and efficient software",
            currentVersion: "1.77.0",
            type: .formula
        )

        XCTAssertEqual(item.id, "rust")
        XCTAssertEqual(item.currentVersion, "1.77.0")
        XCTAssertFalse(item.updateAvailable)
    }

    func testSemanticSearchAndRanking() {
        let items = [
            FormulaItem(id: "python@3.11", name: "python@3.11", description: "Interpreted high-level language", currentVersion: "3.11.8", type: .formula),
            FormulaItem(id: "postgresql@16", name: "postgresql@16", description: "Object-relational database system", currentVersion: "16.2", type: .formula),
            FormulaItem(id: "visual-studio-code", name: "visual-studio-code", description: "Popular open source code editor", currentVersion: "1.85.0", type: .cask)
        ]

        // Test alias expansion & semantic lookup for "database"
        let dbResults = SemanticSearchEngine.searchAndRank(items: items, query: "database")
        XCTAssertFalse(dbResults.isEmpty)
        XCTAssertEqual(dbResults.first?.id, "postgresql@16")

        // Test alias expansion for "py" -> "python"
        let pyResults = SemanticSearchEngine.searchAndRank(items: items, query: "py")
        XCTAssertFalse(pyResults.isEmpty)
        XCTAssertEqual(pyResults.first?.id, "python@3.11")

        // Test "editor" -> "visual-studio-code"
        let editorResults = SemanticSearchEngine.searchAndRank(items: items, query: "editor")
        XCTAssertFalse(editorResults.isEmpty)
        XCTAssertEqual(editorResults.first?.id, "visual-studio-code")
    }

    func testUpdateAvailabilityReconciliation() {
        // Simulates the reconciliation logic in BrewService.checkForUpdates()
        let installedPackages = [
            FormulaItem(id: "git", name: "git", description: "Distributed revision control system", currentVersion: "2.42.0", type: .formula),
            FormulaItem(id: "node", name: "node", description: "Platform built on V8", currentVersion: "20.0.0", type: .formula),
            FormulaItem(id: "python@3.11", name: "python@3.11", description: "Interpreted language", currentVersion: "3.11.8", type: .formula),
            FormulaItem(id: "visual-studio-code", name: "visual-studio-code", description: "Code editor", currentVersion: "1.85.0", type: .cask)
        ]

        // Only git and visual-studio-code have updates available
        let availableUpdates = [
            FormulaItem(id: "git", name: "git", description: "Distributed revision control system", currentVersion: "2.42.0", latestVersion: "2.43.0", type: .formula, updateAvailable: true),
            FormulaItem(id: "visual-studio-code", name: "visual-studio-code", description: "Code editor", currentVersion: "1.85.0", latestVersion: "1.86.0", type: .cask, updateAvailable: true)
        ]

        // Reconcile update availability into installed packages (mirroring BrewService logic)
        let updateIds = Set(availableUpdates.map { $0.id })
        let reconciledPackages = installedPackages.map { item in
            let hasUpdate = updateIds.contains(item.id)
            return FormulaItem(
                id: item.id,
                name: item.name,
                fullTitle: item.fullTitle,
                description: item.description,
                currentVersion: item.currentVersion,
                latestVersion: item.latestVersion,
                type: item.type,
                homepage: item.homepage,
                repository: item.repository,
                license: item.license,
                sizeInBytes: item.sizeInBytes,
                installedDate: item.installedDate,
                lastChecked: item.lastChecked,
                updateAvailable: hasUpdate,
                isPinned: item.isPinned,
                isAutoUpdateEnabled: item.isAutoUpdateEnabled,
                dependencies: item.dependencies,
                versions: item.versions
            )
        }

        // Verify packages with updates are marked correctly
        let gitPackage = reconciledPackages.first { $0.id == "git" }
        XCTAssertNotNil(gitPackage)
        XCTAssertTrue(gitPackage!.updateAvailable, "git should have updateAvailable = true")

        let vscodePackage = reconciledPackages.first { $0.id == "visual-studio-code" }
        XCTAssertNotNil(vscodePackage)
        XCTAssertTrue(vscodePackage!.updateAvailable, "visual-studio-code should have updateAvailable = true")

        // Verify packages without updates are marked correctly
        let nodePackage = reconciledPackages.first { $0.id == "node" }
        XCTAssertNotNil(nodePackage)
        XCTAssertFalse(nodePackage!.updateAvailable, "node should have updateAvailable = false")

        let pythonPackage = reconciledPackages.first { $0.id == "python@3.11" }
        XCTAssertNotNil(pythonPackage)
        XCTAssertFalse(pythonPackage!.updateAvailable, "python@3.11 should have updateAvailable = false")
    }

    // MARK: - CacheManager Tests

    func testCacheManagerDistinguishesSlashFromUnderscore() async {
        let cacheManager = CacheManager()

        // Clear any existing cache
        await cacheManager.clearAllCache()

        // Store data with keys that would collide under the old lossy encoding
        let dataWithSlash = "data for formula/foo".data(using: .utf8)!
        let dataWithUnderscore = "data for formula_foo".data(using: .utf8)!

        await cacheManager.cacheData(dataWithSlash, forKey: "formula/foo")
        await cacheManager.cacheData(dataWithUnderscore, forKey: "formula_foo")

        // Retrieve and verify they remain distinct
        let retrievedSlash = await cacheManager.cachedData(forKey: "formula/foo")
        let retrievedUnderscore = await cacheManager.cachedData(forKey: "formula_foo")

        XCTAssertNotNil(retrievedSlash, "Data for 'formula/foo' should be retrievable")
        XCTAssertNotNil(retrievedUnderscore, "Data for 'formula_foo' should be retrievable")

        XCTAssertEqual(retrievedSlash, dataWithSlash, "Data for 'formula/foo' should match what was stored")
        XCTAssertEqual(retrievedUnderscore, dataWithUnderscore, "Data for 'formula_foo' should match what was stored")

        // Verify the values are different (not colliding)
        XCTAssertNotEqual(retrievedSlash, retrievedUnderscore, "Keys 'formula/foo' and 'formula_foo' must produce distinct cache entries")
    }

    func testCacheManagerRoundTrip() async {
        let cacheManager = CacheManager()

        await cacheManager.clearAllCache()

        let testKeys = [
            "simple",
            "with/slash",
            "with_underscore",
            "multiple/slashes/here",
            "mixed/slash_and_underscore",
            "cask/homebrew/cask/visual-studio-code",
            "formula_info"
        ]

        // Store data for each key
        for key in testKeys {
            let data = "value for \(key)".data(using: .utf8)!
            await cacheManager.cacheData(data, forKey: key)
        }

        // Verify each key retrieves its correct value
        for key in testKeys {
            let expectedData = "value for \(key)".data(using: .utf8)!
            let retrievedData = await cacheManager.cachedData(forKey: key)

            XCTAssertNotNil(retrievedData, "Should retrieve data for key '\(key)'")
            XCTAssertEqual(retrievedData, expectedData, "Retrieved data should match for key '\(key)'")
        }
    }

    func testCacheManagerClearAllCache() async {
        let cacheManager = CacheManager()

        // Store some data
        let data = "test data".data(using: .utf8)!
        await cacheManager.cacheData(data, forKey: "test/key")

        // Verify it was stored
        let beforeClear = await cacheManager.cachedData(forKey: "test/key")
        XCTAssertNotNil(beforeClear)

        // Clear and verify it's gone
        await cacheManager.clearAllCache()
        let afterClear = await cacheManager.cachedData(forKey: "test/key")
        XCTAssertNil(afterClear, "Cache should be empty after clearAllCache()")
    }

    // MARK: - ProcessManager Tests

    func testProcessManagerCapturesFullStdout() async throws {
        let processManager = ProcessManager()

        // Generate a known amount of output to verify full capture
        let lineCount = 100
        // Note: Using deprecated shell method for test that requires shell loop constructs
        let result = try await processManager.executeShellCommand(
            "for i in $(seq 1 \(lineCount)); do echo \"line $i\"; done",
            timeout: 30
        )

        let lines = result.split(separator: "\n")
        XCTAssertEqual(lines.count, lineCount, "Should capture all \(lineCount) lines of stdout")
        XCTAssertTrue(result.contains("line 1"), "Should contain first line")
        XCTAssertTrue(result.contains("line \(lineCount)"), "Should contain last line")
    }

    func testProcessManagerCapturesFullStderr() async {
        let processManager = ProcessManager()

        // Command that outputs to stderr and exits with non-zero
        let lineCount = 50
        do {
            // Note: Using deprecated shell method for test that requires shell loop constructs
            _ = try await processManager.executeShellCommand(
                "for i in $(seq 1 \(lineCount)); do echo \"error $i\" >&2; done; exit 1",
                timeout: 30
            )
            XCTFail("Command should have failed")
        } catch let error as BrewBarError {
            if case .commandFailed(_, let errorMessage) = error {
                let lines = errorMessage.split(separator: "\n")
                XCTAssertEqual(lines.count, lineCount, "Should capture all \(lineCount) lines of stderr")
                XCTAssertTrue(errorMessage.contains("error 1"), "Should contain first error line")
                XCTAssertTrue(errorMessage.contains("error \(lineCount)"), "Should contain last error line")
            } else {
                XCTFail("Expected commandFailed error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testProcessManagerStreamingOutputHandler() async throws {
        let processManager = ProcessManager()
        var streamedOutput = ""
        let streamLock = NSLock()

        // Note: Using deprecated shell method for test that requires shell constructs
        let result = try await processManager.executeShellCommand(
            "echo 'first'; sleep 0.1; echo 'second'; sleep 0.1; echo 'third'",
            timeout: 30,
            outputHandler: { chunk in
                streamLock.lock()
                streamedOutput += chunk
                streamLock.unlock()
            }
        )

        // Verify streaming captured the same content as final result
        XCTAssertTrue(streamedOutput.contains("first"), "Streamed output should contain 'first'")
        XCTAssertTrue(streamedOutput.contains("second"), "Streamed output should contain 'second'")
        XCTAssertTrue(streamedOutput.contains("third"), "Streamed output should contain 'third'")
        XCTAssertEqual(
            result.replacingOccurrences(of: "\n", with: ""),
            streamedOutput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: ""),
            "Streamed output should match final result content"
        )
    }

    func testProcessManagerTimeout() async {
        let processManager = ProcessManager()

        do {
            // Note: Using deprecated shell method for simple shell command
            _ = try await processManager.executeShellCommand(
                "sleep 10",
                timeout: 0.5
            )
            XCTFail("Command should have timed out")
        } catch let error as BrewBarError {
            if case .commandTimeout(let cmd) = error {
                XCTAssertTrue(cmd.contains("sleep"), "Timeout error should contain the command")
            } else {
                XCTFail("Expected commandTimeout error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testProcessManagerSuccessfulCommand() async throws {
        let processManager = ProcessManager()

        // Test direct execution with BrewCommand
        let command = BrewCommand(executablePath: "/bin/echo", arguments: ["hello", "world"])
        let result = try await processManager.execute(command: command, timeout: 30)

        XCTAssertEqual(result, "hello world")
    }

    func testProcessManagerFailedCommand() async {
        let processManager = ProcessManager()

        do {
            // Note: Using deprecated shell method for test that requires shell exit code
            _ = try await processManager.executeShellCommand(
                "exit 42",
                timeout: 30
            )
            XCTFail("Command should have failed")
        } catch let error as BrewBarError {
            if case .commandFailed = error {
                // Expected
            } else {
                XCTFail("Expected commandFailed error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testProcessManagerDirectExecution() async throws {
        let processManager = ProcessManager()

        // Test that direct execution works correctly
        let command = BrewCommand(executablePath: "/bin/ls", arguments: ["-la", "/tmp"])
        let result = try await processManager.execute(command: command, timeout: 30)

        XCTAssertTrue(result.contains("total"), "ls output should contain 'total'")
    }

    func testProcessManagerRejectsNonExistentExecutable() async {
        let processManager = ProcessManager()

        let command = BrewCommand(executablePath: "/nonexistent/path/to/brew", arguments: ["list"])

        do {
            _ = try await processManager.execute(command: command, timeout: 5)
            XCTFail("Should have thrown for non-existent executable")
        } catch let error as BrewBarError {
            if case .homebrewNotInstalled = error {
                // Expected behavior - non-existent executable reports homebrewNotInstalled
            } else {
                XCTFail("Expected homebrewNotInstalled error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Shell Injection Prevention Tests

    func testBrewCommandBuilderPreventsPathInjection() {
        // Test that even if a malicious brewPath is set, it won't be executed via shell
        let maliciousPath = "/tmp/brew; rm -rf ~"
        let builder = BrewCommandBuilder(brewPath: maliciousPath)
        let cmd = builder.install("python").buildCommand()

        // The path should be stored literally, not interpreted
        XCTAssertEqual(cmd.executablePath, maliciousPath)
        XCTAssertEqual(cmd.arguments, ["install", "python"])

        // When executed, this would fail because the literal path doesn't exist,
        // NOT execute the injected command
    }

    func testBrewCommandBuilderSanitizesFormulaName() {
        let builder = BrewCommandBuilder(brewPath: "/usr/local/bin/brew")

        // Test that shell metacharacters are stripped from formula names
        let maliciousFormula = "python; rm -rf ~"
        let cmd = builder.install(maliciousFormula).buildCommand()

        // The formula name should have dangerous characters removed
        XCTAssertEqual(cmd.arguments, ["install", "pythonrm-rf"])
        XCTAssertFalse(cmd.arguments.contains(";"), "Semicolons should be stripped")
        XCTAssertFalse(cmd.arguments.contains("~"), "Tilde should be stripped")
    }

    func testBrewCommandBuilderSanitizesSpecialCharacters() {
        let builder = BrewCommandBuilder(brewPath: "/usr/local/bin/brew")

        // Test various injection attempts
        let testCases = [
            ("$(whoami)", "whoami"),           // Command substitution
            ("`whoami`", "whoami"),            // Backtick substitution
            ("formula && rm -rf /", "formularm-rf"),  // Command chaining
            ("formula || rm -rf /", "formularm-rf"),  // Command chaining
            ("formula | cat /etc/passwd", "formulacatetcpasswd"),  // Pipe
            ("formula > /tmp/malicious", "formulatmpmalicious"),   // Redirect
            ("formula\nrm -rf /", "formularm-rf/"),                // Newline injection
        ]

        for (input, expected) in testCases {
            let cmd = builder.install(input).buildCommand()
            XCTAssertEqual(cmd.arguments[1], expected, "Input '\(input)' should be sanitized to '\(expected)'")
        }
    }

    func testProcessManagerDoesNotInvokeShellForBrewCommands() async throws {
        let processManager = ProcessManager()

        // Create a command with shell metacharacters in the arguments
        // If shell interpretation were happening, this would fail differently
        let command = BrewCommand(
            executablePath: "/bin/echo",
            arguments: ["test; echo INJECTED", "$(whoami)", "`whoami`"]
        )

        let result = try await processManager.execute(command: command, timeout: 5)

        // If executed via shell, we'd see "INJECTED" or the username
        // With direct execution, we see the literal strings
        XCTAssertTrue(result.contains("test; echo INJECTED"), "Shell metacharacters should be treated literally")
        XCTAssertTrue(result.contains("$(whoami)"), "Command substitution should be treated literally")
        XCTAssertTrue(result.contains("`whoami`"), "Backtick substitution should be treated literally")
        XCTAssertFalse(result.contains("INJECTED\n"), "Shell injection should not execute")
    }

    func testBrewCommandEquality() {
        let cmd1 = BrewCommand(executablePath: "/usr/local/bin/brew", arguments: ["install", "python"])
        let cmd2 = BrewCommand(executablePath: "/usr/local/bin/brew", arguments: ["install", "python"])
        let cmd3 = BrewCommand(executablePath: "/opt/homebrew/bin/brew", arguments: ["install", "python"])

        XCTAssertEqual(cmd1, cmd2)
        XCTAssertNotEqual(cmd1, cmd3)
    }

    // MARK: - HomebrewPath Tests

    func testHomebrewPathDefaultIsArchitectureSpecific() {
        // On Apple Silicon, default should be /opt/homebrew/bin/brew
        // On Intel, default should be /usr/local/bin/brew
        #if arch(arm64)
        XCTAssertEqual(HomebrewPath.defaultBrewExecutable, "/opt/homebrew/bin/brew",
                       "Apple Silicon should default to /opt/homebrew/bin/brew")
        #else
        XCTAssertEqual(HomebrewPath.defaultBrewExecutable, "/usr/local/bin/brew",
                       "Intel should default to /usr/local/bin/brew")
        #endif
    }

    func testHomebrewPathConstants() {
        XCTAssertEqual(HomebrewPath.appleSiliconBrewPath, "/opt/homebrew/bin/brew")
        XCTAssertEqual(HomebrewPath.intelBrewPath, "/usr/local/bin/brew")
    }

    func testUserPreferencesDefaultHomebrewPrefix() {
        let prefs = UserPreferences()
        XCTAssertEqual(prefs.homebrewPrefix, HomebrewPath.defaultBrewExecutable,
                       "UserPreferences should default to architecture-appropriate Homebrew path")
    }

    func testBrewCommandBuilderDefaultPath() {
        let builder = BrewCommandBuilder()
        let cmd = builder.install("test").buildCommand()
        XCTAssertEqual(cmd.executablePath, HomebrewPath.defaultBrewExecutable,
                       "BrewCommandBuilder should default to architecture-appropriate Homebrew path")
    }
}
