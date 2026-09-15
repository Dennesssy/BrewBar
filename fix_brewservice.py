import sys

path = "/Users/denn/Desktop/Xcode/BrewBar/Sources/BrewBarKit/Services/BrewService.swift"
with open(path, "r") as f:
    content = f.read()

# For upgradeAll, we want to call refreshInstalledPackages() and checkForUpdates() in the catch block too.
old_catch = """        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            throw handled
        }"""
new_catch = """        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            // Even if it failed (e.g., 1 cask out of 25 failed), refresh the state!
            try? await refreshInstalledPackages()
            try? await checkForUpdates()
            throw handled
        }"""

content = content.replace(old_catch, new_catch)

with open(path, "w") as f:
    f.write(content)
